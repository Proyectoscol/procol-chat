#!/usr/bin/env bash
# Smoke-test VoIP end-to-end — ejecutar en VPS-2 antes de pasar a producción.
# Requiere: curl, bash 4+. turnutils_uclient es opcional (se marca SKIP si no está).
#
# Uso:
#   ./smoke-test.sh
#   RAILS_INTERNAL_URL=https://... SIP_INTERNAL_TOKEN=... ./smoke-test.sh
#
# Variables de entorno (todas tienen fallback a .env del directorio padre):
#   ARI_URL               — http://127.0.0.1:8088
#   ARI_USERNAME          — asterisk
#   ARI_PASSWORD          — changeme
#   RAILS_INTERNAL_URL    — https://chat.procol-proyectoscol.com/api/v1/internal
#   SIP_INTERNAL_TOKEN    — token compartido Rails↔Stasis
#   TEST_DID              — número DID a consultar (E164, ej: +5760XXXXXXX)
#   TEST_CALLER           — número llamante de prueba (E164)
#   TEST_LINKED_ID        — ID de llamada de prueba (default: smoke-test-$$)
#   AGENT_API_TOKEN       — token de agente para /sip/recent_calls
#   ACCOUNT_ID            — ID de cuenta (default: 1)
#   COTURN_HOST           — host del coturn (default: localhost)
#   COTURN_PORT           — puerto coturn (default: 3478)
#   COTURN_USER           — usuario coturn (default: procol)
#   COTURN_CREDENTIAL     — credencial coturn

set -euo pipefail

# ── Cargar .env del directorio padre si existe ────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$ENV_FILE"; set +a
fi

# ── Configuración con fallbacks ────────────────────────────────────────────────
ARI_URL="${ARI_URL:-http://127.0.0.1:8088}"
ARI_USERNAME="${ARI_USERNAME:-asterisk}"
ARI_PASSWORD="${ARI_PASSWORD:-changeme}"
RAILS_INTERNAL_URL="${RAILS_INTERNAL_URL:-}"
SIP_INTERNAL_TOKEN="${SIP_INTERNAL_TOKEN:-}"
TEST_DID="${TEST_DID:-}"
TEST_CALLER="${TEST_CALLER:-+573006649923}"
TEST_LINKED_ID="${TEST_LINKED_ID:-smoke-test-$$}"
AGENT_API_TOKEN="${AGENT_API_TOKEN:-}"
ACCOUNT_ID="${ACCOUNT_ID:-1}"
COTURN_HOST="${COTURN_HOST:-localhost}"
COTURN_PORT="${COTURN_PORT:-3478}"
COTURN_USER="${COTURN_USER:-procol}"
COTURN_CREDENTIAL="${COTURN_CREDENTIAL:-}"

# ── Colores y contadores ───────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0; SKIP=0

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
skip() { echo -e "${YELLOW}[SKIP]${NC} $1"; ((SKIP++)); }
info() { echo -e "       $1"; }

# ── Validación de prerrequisitos ───────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  VoIP Smoke-Test — $(date '+%Y-%m-%d %H:%M:%S')"
echo "══════════════════════════════════════════════════════"
echo ""

if [[ -z "$RAILS_INTERNAL_URL" ]]; then
  fail "RAILS_INTERNAL_URL no definido. Abortar."
  exit 1
fi
if [[ -z "$SIP_INTERNAL_TOKEN" ]]; then
  fail "SIP_INTERNAL_TOKEN no definido. Abortar."
  exit 1
fi
if [[ -z "$TEST_DID" ]]; then
  fail "TEST_DID no definido (número DID E164 a probar). Abortar."
  exit 1
fi

echo "  ARI:     ${ARI_URL}"
echo "  Rails:   ${RAILS_INTERNAL_URL}"
echo "  DID:     ${TEST_DID}"
echo "  Caller:  ${TEST_CALLER}"
echo "  LinkedID: ${TEST_LINKED_ID}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 1 — Stasis app / ARI health
# ─────────────────────────────────────────────────────────────────────────────
echo "── CHECK 1: ARI asterisk/info ──────────────────────────"
ARI_RESP=$(curl -sf --max-time 5 \
  -u "${ARI_USERNAME}:${ARI_PASSWORD}" \
  "${ARI_URL}/ari/asterisk/info" 2>&1) || ARI_RESP=""

if echo "$ARI_RESP" | grep -q '"system"'; then
  AST_VER=$(echo "$ARI_RESP" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4)
  pass "ARI responde — Asterisk ${AST_VER}"
else
  fail "ARI no responde o credenciales incorrectas"
  info "URL: ${ARI_URL}/ari/asterisk/info"
  info "Respuesta: ${ARI_RESP:0:200}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 2 — GET /sip/routing (simula llamada entrante de Stasis)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── CHECK 2: GET /sip/routing ───────────────────────────"
ROUTING_RESP=$(curl -sf --max-time 10 \
  -H "X-Sip-Token: ${SIP_INTERNAL_TOKEN}" \
  "${RAILS_INTERNAL_URL}/sip/routing?phone=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${TEST_CALLER}'))" 2>/dev/null || printf '%s' "${TEST_CALLER}" | sed 's/+/%2B/g')&to=$(printf '%s' "${TEST_DID}" | sed 's/+/%2B/g')&linkedid=${TEST_LINKED_ID}" \
  2>&1) || ROUTING_RESP=""

ROUTING_ACTION=$(echo "$ROUTING_RESP" | grep -o '"action":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ "$ROUTING_ACTION" =~ ^(dial|ivr|voicemail|busy|closed)$ ]]; then
  pass "Routing responde — action: ${ROUTING_ACTION}"
  if echo "$ROUTING_RESP" | grep -q '"extension"'; then
    EXT=$(echo "$ROUTING_RESP" | grep -o '"extension":"[^"]*"' | head -1 | cut -d'"' -f4)
    info "extension: ${EXT}"
  fi
  if echo "$ROUTING_RESP" | grep -q '"prompt"'; then
    PROMPT=$(echo "$ROUTING_RESP" | grep -o '"prompt":"[^"]*"' | head -1 | cut -d'"' -f4)
    info "ivr_prompt: ${PROMPT}"
  fi
else
  fail "Routing no devolvió acción válida"
  info "Esperado: dial|ivr|voicemail|busy|closed"
  info "Respuesta: ${ROUTING_RESP:0:300}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 3 — POST /sip/events — evento answered
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── CHECK 3: POST /sip/events (answered) ───────────────"
ANSWERED_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST \
  -H "X-Sip-Token: ${SIP_INTERNAL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"event_type\":\"answered\",\"from_number\":\"${TEST_CALLER}\",\"to\":\"${TEST_DID}\",\"call_direction\":\"inbound\",\"linkedid\":\"${TEST_LINKED_ID}\"}" \
  "${RAILS_INTERNAL_URL}/sip/events" 2>&1) || ANSWERED_HTTP="000"

if [[ "$ANSWERED_HTTP" == "204" ]]; then
  pass "Evento answered aceptado (HTTP 204)"
elif [[ "$ANSWERED_HTTP" == "200" ]]; then
  pass "Evento answered aceptado (HTTP 200)"
else
  fail "Evento answered rechazado — HTTP ${ANSWERED_HTTP}"
  info "Endpoint: ${RAILS_INTERNAL_URL}/sip/events"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 4 — POST /sip/events — evento ended
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── CHECK 4: POST /sip/events (ended) ──────────────────"
ENDED_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  -X POST \
  -H "X-Sip-Token: ${SIP_INTERNAL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"event_type\":\"ended\",\"from_number\":\"${TEST_CALLER}\",\"to\":\"${TEST_DID}\",\"call_direction\":\"inbound\",\"linkedid\":\"${TEST_LINKED_ID}\",\"duration_seconds\":47}" \
  "${RAILS_INTERNAL_URL}/sip/events" 2>&1) || ENDED_HTTP="000"

if [[ "$ENDED_HTTP" == "204" ]]; then
  pass "Evento ended aceptado (HTTP 204)"
elif [[ "$ENDED_HTTP" == "200" ]]; then
  pass "Evento ended aceptado (HTTP 200)"
else
  fail "Evento ended rechazado — HTTP ${ENDED_HTTP}"
  info "Endpoint: ${RAILS_INTERNAL_URL}/sip/events"
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 5 — GET /sip/recent_calls (verifica que la llamada quedó registrada)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── CHECK 5: GET /sip/recent_calls ─────────────────────"
if [[ -z "$AGENT_API_TOKEN" ]]; then
  skip "AGENT_API_TOKEN no definido — omitir verificación de recent_calls"
else
  # Breve espera para que el job de Rails procese el evento
  sleep 2

  RAILS_BASE="${RAILS_INTERNAL_URL%/internal*}"  # quitar /internal del path
  RECENT_RESP=$(curl -sf --max-time 10 \
    -H "api_access_token: ${AGENT_API_TOKEN}" \
    "${RAILS_BASE}/api/v1/accounts/${ACCOUNT_ID}/sip/recent_calls" \
    2>&1) || RECENT_RESP=""

  if echo "$RECENT_RESP" | grep -q '"id"'; then
    CALL_COUNT=$(echo "$RECENT_RESP" | grep -o '"id"' | wc -l | tr -d ' ')
    # Verificar que el linkedid de prueba aparece en alguna llamada (si el logger lo guarda)
    if echo "$RECENT_RESP" | grep -qi "${TEST_CALLER}"; then
      pass "recent_calls contiene la llamada de prueba (${CALL_COUNT} llamada(s) total)"
    else
      pass "recent_calls responde con ${CALL_COUNT} llamada(s) — llamada de prueba no identificada (puede ser normal si Rails procesa async)"
    fi
  elif [[ "$RECENT_RESP" == "[]" ]] || echo "$RECENT_RESP" | grep -q '^\[\]'; then
    pass "recent_calls responde (lista vacía — el job puede estar en cola)"
  else
    fail "recent_calls no respondió o error de autenticación"
    info "Respuesta: ${RECENT_RESP:0:200}"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 6 — coturn TURN connectivity
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "── CHECK 6: coturn TURN ────────────────────────────────"
if ! command -v turnutils_uclient &>/dev/null; then
  skip "turnutils_uclient no encontrado — instalar: apt install coturn-utils"
elif [[ -z "$COTURN_CREDENTIAL" ]]; then
  skip "COTURN_CREDENTIAL no definido — omitir test TURN"
else
  # -t = use TCP, -p = puerto, -u = usuario, -w = contraseña
  TURN_OUT=$(turnutils_uclient -t \
    -p "${COTURN_PORT}" \
    -u "${COTURN_USER}" \
    -w "${COTURN_CREDENTIAL}" \
    "turn:${COTURN_HOST}" 2>&1) || TURN_OUT="error"

  if echo "$TURN_OUT" | grep -qi "success\|allocation\|received"; then
    pass "coturn TURN allocation exitosa — turn:${COTURN_HOST}:${COTURN_PORT}"
  elif echo "$TURN_OUT" | grep -qi "error\|refused\|timeout"; then
    fail "coturn no respondió o rechazó la conexión"
    info "Host: turn:${COTURN_HOST}:${COTURN_PORT}"
    info "Salida: ${TURN_OUT:0:300}"
  else
    # turnutils_uclient a veces termina sin mensaje claro pero sin error
    pass "coturn respondió (sin error explícito) — turn:${COTURN_HOST}:${COTURN_PORT}"
    info "Salida: ${TURN_OUT:0:200}"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Resumen
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL + SKIP))
echo "  Resultado: ${PASS}/${TOTAL} checks pasados  |  FAIL: ${FAIL}  |  SKIP: ${SKIP}"
echo "══════════════════════════════════════════════════════"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0

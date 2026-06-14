#!/usr/bin/env bash
# Instala o actualiza la Stasis app en VPS-2 (idempotente).
# Ejecutar como root desde el repo clonado:
#   sudo bash deploy/asterisk-stasis/deploy.sh
set -euo pipefail

APP_DIR=/opt/procol-stasis
SERVICE_NAME=procol-stasis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Prerrequisitos ────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  echo "ERROR: Node.js no encontrado. Instalar Node >= 18 primero." >&2
  exit 1
fi

NODE_VER=$(node -e "process.exit(parseInt(process.versions.node) < 18 ? 1 : 0)" 2>/dev/null && echo ok || echo old)
if [[ "$NODE_VER" == "old" ]]; then
  echo "ERROR: Node.js >= 18 requerido (actual: $(node --version))." >&2
  exit 1
fi

# ── Crear directorio destino ──────────────────────────────────────────────────
mkdir -p "$APP_DIR"

# ── Sincronizar archivos de la app ────────────────────────────────────────────
echo "→ Copiando archivos a ${APP_DIR}..."
cp -r "${SCRIPT_DIR}/src"              "$APP_DIR/"
cp    "${SCRIPT_DIR}/package.json"     "$APP_DIR/"
cp    "${SCRIPT_DIR}/.env.example"     "$APP_DIR/"

# ── Configuración (.env) ──────────────────────────────────────────────────────
if [[ ! -f "${APP_DIR}/.env" ]]; then
  cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ACCIÓN REQUERIDA: editar ${APP_DIR}/.env"
  echo "  Rellenar: ARI_PASSWORD, RAILS_INTERNAL_URL,"
  echo "            SIP_INTERNAL_TOKEN, FALLBACK_CONTEXT"
  echo "  Luego volver a ejecutar este script."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  exit 1
fi

# ── Instalar dependencias ─────────────────────────────────────────────────────
echo "→ Instalando dependencias npm..."
cd "$APP_DIR"
npm ci --production --silent

# ── Instalar/actualizar servicio systemd ─────────────────────────────────────
echo "→ Instalando servicio systemd..."
cp "${SCRIPT_DIR}/stasis.service" "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# ── Verificar health check ────────────────────────────────────────────────────
echo "→ Esperando arranque del servicio..."
sleep 3

if curl -sf --max-time 5 "http://localhost:3001/" | grep -q '"ok"'; then
  UPTIME=$(curl -sf http://localhost:3001/ | grep -o '"uptime":[0-9]*' | cut -d: -f2)
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  OK — Stasis app corriendo (uptime: ${UPTIME}s)"
  echo "  Logs: journalctl -u ${SERVICE_NAME} -f"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo ""
  echo "FAIL — Stasis app no responde en http://localhost:3001/" >&2
  echo "  journalctl -u ${SERVICE_NAME} --no-pager -n 30" >&2
  exit 1
fi

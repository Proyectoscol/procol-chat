#!/usr/bin/env bash
# Verifica y crea el contexto procol-voice (Stasis routing) en
# /etc/asterisk/extensions_custom.conf si no existe.
# Idempotente: solo escribe si el contexto [procol-voice] no está presente.
#
# Uso:
#   sudo bash setup-dialplan.sh
set -euo pipefail

CONF=/etc/asterisk/extensions_custom.conf

# Crear el archivo si FreePBX aún no lo generó.
if [[ ! -f "$CONF" ]]; then
  touch "$CONF"
  echo "→ Creado ${CONF}"
fi

# ── Contexto principal: entrega a la app Stasis ───────────────────────────────
if grep -qF "[procol-voice]" "$CONF"; then
  echo "Contexto [procol-voice] ya existe en ${CONF} — sin cambios."
else
  cat >> "$CONF" << 'DIALPLAN'

; Contexto que entrega la llamada entrante a la Stasis app (procol-stasis).
; En FreePBX: Inbound Route → Custom Destination → "procol-voice,s,1".
[procol-voice]
exten => s,1,NoOp(Entrega a Stasis procol-routing - llamada entrante)
 same => n,Stasis(procol-routing)
 same => n,Hangup()
DIALPLAN

  echo "→ Contexto [procol-voice] agregado"
fi

# ── Contexto de fallback ──────────────────────────────────────────────────────
if grep -qF "[from-voicemail]" "$CONF"; then
  echo "Contexto [from-voicemail] ya existe en ${CONF} — sin cambios."
else
  cat >> "$CONF" << 'DIALPLAN'

; Fallback: si la Stasis app no está corriendo o Rails no responde.
; FALLBACK_CONTEXT en /opt/procol-stasis/.env debe apuntar a este contexto.
[from-voicemail]
exten => s,1,NoOp(Fallback - sin asesor o routing caido)
 same => n,Playback(vm-nobodyavail)
 same => n,VoiceMail(general@default,u)
 same => n,Hangup()
DIALPLAN

  echo "→ Contexto [from-voicemail] agregado"
fi

# ── Recargar dialplan ─────────────────────────────────────────────────────────
if asterisk -rx "dialplan reload" 2>&1 | grep -qi "error\|failed"; then
  echo "WARN: dialplan recargó con advertencias — revisar logs de Asterisk" >&2
else
  echo "→ Dialplan recargado OK"
fi

echo ""
echo "Siguiente paso en FreePBX UI:"
echo "  Inbound Routes → <ruta DID> → Set Destination → Custom Destination"
echo "  Destination: procol-voice,s,1"

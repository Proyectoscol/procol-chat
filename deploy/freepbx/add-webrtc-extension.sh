#!/usr/bin/env bash
# Agrega los parámetros WebRTC (ice_support, use_avpf) a una extensión PJSIP
# existente en FreePBX mediante un override en pjsip.endpoint_custom_post.conf.
# Idempotente: si la extensión ya tiene el bloque, no hace nada.
#
# Uso:
#   sudo bash add-webrtc-extension.sh <extension>
#   sudo bash add-webrtc-extension.sh 1001
set -euo pipefail

EXT="${1:-}"
if [[ -z "$EXT" ]]; then
  echo "Uso: $0 <extension>"
  echo "Ejemplo: $0 1001"
  exit 1
fi

CONF=/etc/asterisk/pjsip.endpoint_custom_post.conf

# Crear el archivo si no existe (FreePBX lo crea al primer uso, pero por si acaso).
if [[ ! -f "$CONF" ]]; then
  touch "$CONF"
  echo "→ Creado ${CONF}"
fi

# Idempotencia: salir si el bloque ya existe.
if grep -qF "[$EXT]" "$CONF"; then
  echo "Extensión ${EXT} ya existe en ${CONF} — sin cambios."
  exit 0
fi

# Agregar el bloque de override WebRTC.
cat >> "$CONF" << EOF

[$EXT](+)
ice_support=yes
use_avpf=yes
EOF

echo "→ Bloque WebRTC agregado para extensión ${EXT}"

# Recargar el módulo PJSIP en Asterisk.
if asterisk -rx "module reload res_pjsip.so" 2>&1 | grep -qi "error\|failed"; then
  echo "WARN: pjsip recargó con advertencias — revisar 'asterisk -rx core show version'" >&2
else
  echo "→ res_pjsip.so recargado OK"
fi

echo "Extensión ${EXT} configurada con WebRTC (ice_support=yes, use_avpf=yes)"

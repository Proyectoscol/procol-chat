#!/bin/bash
# Instala y configura coturn (TURN/STUN) en VPS-2.
# Uso: TURN_USERNAME=foo TURN_CREDENTIAL=bar PUBLIC_IP=2.25.200.186 bash install.sh
set -euo pipefail

: "${TURN_USERNAME:?Falta TURN_USERNAME}"
: "${TURN_CREDENTIAL:?Falta TURN_CREDENTIAL}"
: "${PUBLIC_IP:?Falta PUBLIC_IP (IP pública del VPS-2)}"
REALM="${REALM:-freebpx.procol-proyectoscol.com}"

apt-get update -qq
apt-get install -y coturn netfilter-persistent iptables-persistent

# Habilitar el daemon (viene deshabilitado por defecto en el paquete Debian/Ubuntu).
sed -i 's/#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn

mkdir -p /var/log/coturn

cat > /etc/turnserver.conf << EOF
listening-port=3478
tls-listening-port=5349

listening-ip=0.0.0.0
external-ip=${PUBLIC_IP}

realm=${REALM}

# Credenciales estáticas de largo plazo (lt-cred-mech).
# Para credenciales efímeras por sesión (más seguro) usar use-auth-secret
# con static-auth-secret y generar usuario/clave HMAC desde Rails.
lt-cred-mech
user=${TURN_USERNAME}:${TURN_CREDENTIAL}

# Rango de puertos relay (abrir en firewall).
min-port=49152
max-port=65535

log-file=/var/log/coturn/turnserver.log
simple-log

# Endurecimiento
no-multicast-peers
stale-nonce
fingerprint
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
EOF

# Firewall
iptables -C INPUT -p udp --dport 3478 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport 3478 -j ACCEPT
iptables -C INPUT -p tcp --dport 5349 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 5349 -j ACCEPT
iptables -C INPUT -p udp --dport 49152:65535 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p udp --dport 49152:65535 -j ACCEPT
netfilter-persistent save

systemctl enable coturn
systemctl restart coturn
systemctl status coturn --no-pager

echo ""
echo "coturn instalado. Verificar con:"
echo "  journalctl -u coturn -n 30"
echo "  https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/"
echo "  URL: turn:${PUBLIC_IP}:3478  user: ${TURN_USERNAME}  cred: ${TURN_CREDENTIAL}"

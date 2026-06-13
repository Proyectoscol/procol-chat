# coturn — TURN/STUN para WebRTC (VPS-2)

## Por qué

La señalización SIP va por WSS, pero el **audio (RTP)** va navegador↔Asterisk por DTLS-SRTP.
Con NAT simétrico (oficinas, redes móviles) STUN no basta y el audio no fluye. coturn hace de
relay TURN. Sin esto, ~20% de asesores en redes corporativas no tienen audio.

## Variables de entorno requeridas

Agregar en `.env` de VPS-1 (Rails):

| Variable | Descripción |
|----------|-------------|
| `TURN_USERNAME` | Usuario estático para autenticar en coturn |
| `TURN_CREDENTIAL` | Contraseña estática (mínimo 20 chars aleatorios) |
| `SIP_WSS_HOST` | Ya existe — también se usa como host del TURN (`turn:<host>:3478`) |

Rails devuelve estos valores al frontend en `GET /api/v1/accounts/:id/sip/credential`
dentro del array `ice_servers`.

## Instalación en VPS-2

```bash
# Ejecutar como root en VPS-2
TURN_USERNAME=procol_turn \
TURN_CREDENTIAL=__SECRET_MIN_20_CHARS__ \
PUBLIC_IP=2.25.200.186 \
bash deploy/coturn/install.sh
```

El script hace:
1. `apt install coturn`
2. Habilita el daemon en `/etc/default/coturn`
3. Escribe `/etc/turnserver.conf` con los valores del entorno
4. Abre puertos UDP 3478, TCP 5349 y UDP 49152-65535 en iptables
5. `systemctl enable --now coturn`

## Pasos manuales post-instalación

1. Verificar que coturn corre: `systemctl status coturn`
2. Ver logs: `journalctl -u coturn -f`
3. Verificar candidato relay en el browser:
   - Abrir https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/
   - URI: `turn:2.25.200.186:3478`
   - User / Credential: los valores de `TURN_USERNAME` / `TURN_CREDENTIAL`
   - Debe aparecer un candidato de tipo `relay`

## Cómo llega al frontend

`Sip::CredentialService#ice_servers` devuelve:
```json
[
  { "urls": ["stun:stun.l.google.com:19302"] },
  {
    "urls": ["turn:freebpx.procol-proyectoscol.com:3478"],
    "username": "<TURN_USERNAME>",
    "credential": "<TURN_CREDENTIAL>"
  }
]
```

JsSIP usa este array al crear `RTCPeerConnection`. Si `TURN_USERNAME` o `TURN_CREDENTIAL`
no están configurados, solo se devuelve STUN (comportamiento anterior — dev seguro).

## Firewall (puertos requeridos en VPS-2)

| Puerto | Protocolo | Uso |
|--------|-----------|-----|
| 3478 | UDP | STUN/TURN |
| 5349 | TCP | TURN sobre TLS (opcional para MVP) |
| 49152-65535 | UDP | Rango relay de media |

## Mejora futura

El modelo actual usa credenciales estáticas de largo plazo (`lt-cred-mech`). Para producción
con muchos asesores, migrar a `use-auth-secret` en coturn + generación de credenciales
efímeras HMAC en Rails (TTL ~1h por sesión). Evita que una credencial comprometida sea
válida indefinidamente.

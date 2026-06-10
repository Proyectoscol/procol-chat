# coturn — TURN/STUN para WebRTC (VPS-2)

## Por qué
La señalización SIP va por WSS (Asterisk), pero el **audio (RTP)** va navegador↔Asterisk por DTLS-SRTP. Con NAT simétrico (oficinas, redes móviles) STUN no basta y el audio no fluye. coturn hace de relay TURN. Provisionarlo **desde el inicio** (decisión ARQ-2), no después de que falle en producción.

## Setup
```bash
apt install coturn
# /etc/default/coturn → TURNSERVER_ENABLED=1
cp turnserver.conf.example /etc/turnserver.conf   # editar IP pública, secret, cert
systemctl enable --now coturn
```

## Credenciales efímeras (coincide con FIX-11)
`use-auth-secret` + `static-auth-secret` = credenciales TURN de corto plazo. Rails genera usuario/clave temporal (HMAC del secret + timestamp) y los entrega al navegador junto a los ICE servers. Nada estático en el cliente.

Lado Rails: `Call.default_ice_servers` (ya existe) se extiende para incluir el TURN:
```
{ urls: 'turn:turn.tudominio.com:3478', username: <temporal>, credential: <hmac> }
```
ENV: `VOICE_CALL_TURN_URLS`, `VOICE_CALL_TURN_SECRET` (= `static-auth-secret`).

## Firewall
- UDP 3478 (STUN/TURN), TCP/UDP 5349 (TLS).
- UDP 49152-65535 (rango relay).

## Verificar
`https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/` con tu URL TURN + credencial temporal → debe aparecer un candidato `relay`.

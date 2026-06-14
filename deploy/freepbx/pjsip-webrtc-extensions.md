# Configuración PJSIP — Extensiones WebRTC

Cada extensión WebRTC nueva en FreePBX necesita un bloque adicional en
`/etc/asterisk/pjsip.endpoint_custom_post.conf` para habilitar capacidades
WebRTC (ICE, AVPF, DTLS-SRTP).

---

## Por qué es necesario este archivo

FreePBX genera `pjsip.conf` automáticamente desde la GUI. Los ajustes WebRTC
(`webrtc=yes`, `ice_support=yes`, `use_avpf=yes`, `media_encryption=dtls`) NO
están expuestos en la GUI estándar y se sobreescriben al hacer "Apply Config".

El archivo `pjsip.endpoint_custom_post.conf` se incluye **después** de la
configuración generada por FreePBX y no se sobreescribe. Es el lugar seguro
para estos ajustes.

---

## Plantilla por extensión

```ini
; /etc/asterisk/pjsip.endpoint_custom_post.conf
; Agregar un bloque por cada extensión WebRTC.

[200]                          ; Número de extensión FreePBX
type=endpoint
webrtc=yes                     ; Activa ice_support, use_avpf, rtcp_mux, bundle, tos_audio, cos_audio
dtls_cert_file=/etc/asterisk/keys/asterisk.pem
dtls_private_key=/etc/asterisk/keys/asterisk.pem
dtls_ca_file=/etc/asterisk/keys/ca.crt     ; Opcional si el cert es self-signed
dtls_setup=actpass
dtls_auto_generate_cert=yes    ; Eliminar si se usan certs propios

[201]
type=endpoint
webrtc=yes
dtls_auto_generate_cert=yes
dtls_setup=actpass
```

> `webrtc=yes` es un shorthand que activa implícitamente:
> `ice_support=yes`, `use_avpf=yes`, `rtcp_mux=yes`, `bundle=yes`
> No hace falta declararlos de forma explícita si se usa `webrtc=yes`.

---

## Verificación tras aplicar

```bash
# Recargar pjsip sin reiniciar Asterisk
asterisk -rx "module reload res_pjsip.so"

# Confirmar que el endpoint tiene webrtc activo
asterisk -rx "pjsip show endpoint 200"
# Buscar en la salida: media_encryption=dtls, ice_support=true, use_avpf=true

# Ver extensiones registradas (JsSIP conectado)
asterisk -rx "pjsip show registrations"
```

---

## Certificados DTLS

Si `dtls_auto_generate_cert=yes` no funciona (Asterisk < 16.16):

```bash
# Generar certificado self-signed
mkdir -p /etc/asterisk/keys
cd /usr/src/asterisk*/contrib/scripts
./ast_tls_cert -C [IP_O_DOMINIO_FREEPBX] -O "ProCall" -d /etc/asterisk/keys
chown asterisk:asterisk /etc/asterisk/keys/*
```

Actualizar `pjsip.endpoint_custom_post.conf`:
```ini
dtls_cert_file=/etc/asterisk/keys/asterisk.pem
dtls_private_key=/etc/asterisk/keys/asterisk.pem
dtls_auto_generate_cert=no
```

---

## Relación con JsSIP (frontend ProCall)

El cliente JsSIP en el frontend conecta vía WebSocket seguro:
```
wss://[FREEPBX_HOST]:8089/ws
```

Para que la llamada de audio funcione, el handshake DTLS debe completarse.
Si el audio es unidireccional o no hay audio, revisar:

1. `ice_support=yes` activo en el endpoint
2. Puerto STUN/TURN accesible (ver `deploy/coturn/`)
3. `dtls_setup=actpass` en el endpoint (no `active` ni `passive` a secas)
4. Certificado DTLS válido y cargado por Asterisk

Ver también: [Asterisk/FreePBX WebRTC Config](../memory/project_asterisk_webrtc_config.md)

---

## Checklist para nueva extensión WebRTC

- [ ] Crear extensión en FreePBX GUI (`Applications > Extensions > Add`)
- [ ] Anotar el número de extensión asignado
- [ ] Agregar bloque `[NNN]` en `pjsip.endpoint_custom_post.conf`
- [ ] `asterisk -rx "module reload res_pjsip.so"`
- [ ] Verificar con `pjsip show endpoint NNN`
- [ ] Registrar desde el frontend JsSIP y confirmar estado `Registered`
- [ ] Hacer llamada de prueba interna (extensión a extensión)

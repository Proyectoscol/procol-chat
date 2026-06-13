# Asterisk Stasis App — cerebro de routing (VPS-2)

App Node que conecta a Asterisk vía **ARI** (WebSocket local en VPS-2) y decide a qué asesor
suena cada llamada, consultando a Rails. Corre junto a FreePBX/Asterisk, no dentro del repo
Rails.

## Por qué existe

ARI usa WebSocket persistente. Rails/Puma no debe mantener ese socket cross-VPS. Esta app es
el consumidor ARI local; habla con Rails por HTTP stateless. Si Rails cae, aplica **fallback
local** (manda a IVR/cola) y la telefonía no se interrumpe.

## Flujo principal

```
StasisStart (llamada entra al contexto Stasis desde el dialplan de FreePBX)
  │
  ├─ GET /api/v1/internal/sip/routing?phone=<E164>&linkedid=<id>
  │
  ├─ {action:'dial', extension:'1001'}
  │     ├─ originate PJSIP/1001, timeout 30 s
  │     ├─ ChannelStateChange(Up)  → POST /sip/events {event_type:'answered'}
  │     ├─ bridge mixing (caller ↔ agente)
  │     ├─ StasisEnd               → POST /sip/events {event_type:'ended', duration_seconds}
  │     └─ timeout / ChannelDestroyed sin Up
  │           → POST /sip/events {event_type:'no_answer'} → fallback
  │
  ├─ {action:'ivr', prompt:'ivr-ciudades'}
  │     ├─ playback sound:ivr-ciudades, espera dígito DTMF (10 s timeout)
  │     ├─ GET /sip/routing?ivr_digit=<n>&linkedid=<id>  → {action:'dial', extension}
  │     └─ Dial (round-robin hasta que conteste o se agoten asesores)
  │
  ├─ {action:'voicemail'}  → continueInDialplan(FALLBACK_CONTEXT)
  └─ {action:'busy'}       → hangup
```

## Identidad de llamada

Usa **`linkedid`** como identificador estable en todos los POST a Rails (invariante durante
transferencias). El `channel.id` cambia por leg.

## Archivos

| Archivo | Rol |
|---------|-----|
| `src/index.js` | Conexión ARI, despacho StasisStart, presencia SIP |
| `src/routing.js` | Lógica de dial, bridge, IVR, fallback |
| `src/ivr.js` | Playback de prompt + recolección DTMF con timeout |
| `src/events.js` | Reporter de eventos a Rails (answered/ended/no_answer/presencia) |
| `src/railsClient.js` | HTTP client a `/sip/routing` y `/sip/events` |
| `.env.example` | Variables requeridas |
| `stasis.service` | Unit systemd |

## Deploy en VPS-2

### 1. Requisitos

```bash
node --version   # >= 18
# Asegurarse de que ARI esté habilitado en FreePBX:
# Admin → Asterisk REST Interface → Enable ARI = Yes, usuario/pass definidos
```

### 2. Copiar archivos

```bash
mkdir -p /opt/procol-stasis
cp -r deploy/asterisk-stasis/. /opt/procol-stasis/
cd /opt/procol-stasis
npm install --production
```

### 3. Variables de entorno

```bash
cp .env.example .env
# Editar:
#   ARI_USERNAME / ARI_PASSWORD  →  los configurados en FreePBX ARI
#   SIP_INTERNAL_TOKEN           →  mismo valor que SIP_INTERNAL_TOKEN en Rails
#   RAILS_INTERNAL_URL           →  https://chat.procol-proyectoscol.com/api/v1/internal
nano .env
```

### 4. Dialplan FreePBX

Agregar en `Admin → Config Edit → /etc/asterisk/extensions_custom.conf`:

```ini
[from-pstn-custom]
exten => _X.,1,NoOp(Procol Stasis Routing)
 same => n,Stasis(stasis-routing)
 same => n,Hangup()
```

En FreePBX IVR / Inbound Routes, enviar al contexto `from-pstn-custom`.

### 5. Sonidos IVR

```bash
# Convertir audio del menú a formato Asterisk (µ-law / 8 kHz):
ffmpeg -i menu.mp3 -ar 8000 -ac 1 -acodec pcm_mulaw ivr-ciudades.wav
# Subir en FreePBX: Admin → Sound Languages → Upload
# El nombre sin extensión debe coincidir con IVR_PROMPT en .env
```

### 6. Instalar servicio systemd

```bash
cp stasis.service /etc/systemd/system/procol-stasis.service
systemctl daemon-reload
systemctl enable procol-stasis
systemctl start procol-stasis
systemctl status procol-stasis
journalctl -u procol-stasis -f
```

### 7. Verificar

```bash
# ARI responde:
curl -u asterisk:changeme http://localhost:8088/ari/applications
# Debe listar "stasis-routing" después de que la app arranca.

# Token Rails:
curl -H "X-Asterisk-Token: <SIP_INTERNAL_TOKEN>" \
  "https://chat.procol-proyectoscol.com/api/v1/internal/sip/routing?phone=%2B571234567890&linkedid=test"
```

## TODO

- **U3 Presencia real**: reemplazar `DeviceStateChanged` de ARI por conexión AMI que
  escuche `ContactStatus` (Reachable/Unreachable). Al arrancar: `PJSIPShowContacts`
  para sincronizar estado inicial.
- **Audios IVR**: subir `ivr-ciudades` a FreePBX y actualizar `IVR_PROMPT` en `.env`.
- **Transferencia ciega**: validar comportamiento `ChannelTransfer` con `chan_pjsip`; puede
  requerir endpoint HTTP interno que el panel llame en lugar del evento ARI.

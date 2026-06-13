# Contexto VoIP — ProCol Chat (Chatwoot fork)
> Para copiar en un nuevo chat. Generado el 2026-06-13.

---

## ¿Qué estamos construyendo?

Un softphone WebRTC nativo dentro de ProCol Chat (fork de Chatwoot) que le permite a los asesores de servicio al cliente atender **llamadas telefónicas de clientes** directamente desde el navegador, sin app externa. Las llamadas entran por un número de troncal Claro (PSTN) conectado a **FreePBX / Asterisk en VPS-2**, y el browser se registra como extensión SIP via WebSocket (JsSIP).

**Repositorio:** `https://github.com/Proyectoscol/procol-chat`  
**Rama de trabajo:** `custom` (NUNCA commits en `main`)  
**Plan de referencia:** `docs/plans/asterisk-softphone-web-v1.md`

---

## Arquitectura (resumen)

```
VPS-1 (EasyPanel)                     VPS-2 (Hostinger — srv1750665)
  Rails / ProCol Chat                   FreePBX 17.0.28 / Asterisk 22.8.2
    GET  /sip/credential  ◄─────────── Stasis app (Node) pide token
    POST /sip/events      ◄─────────── Stasis app reporta eventos ARI
    GET  /sip/routing     ◄─────────── Stasis app pide a quién llamar

  ActionCable → browser               chan_pjsip (WebRTC endpoints)
                                       coturn (TURN/STUN)
                                       Troncal Claro (PSTN)

Browser asesor (Chrome)
  JsSIP 3.13.8
  SIP/WSS:8089 → freebpx.procol-proyectoscol.com
  DTLS-SRTP media
```

---

## Estado actual por Lanes

### ✅ Lane A — Base de datos y modelos
- `sip_identities` migration: `account_id`, `user_id`, `sip_extension`, `sip_password` (encriptado), `sip_active_contacts`, `sip_last_registered_at`, `sip_absence_alerted_at`, `sip_absence_mode`, tokens FCM/APNs para fase 2
- `SipIdentity` model (UNIQUE por cuenta × extensión, UNIQUE por cuenta × usuario)
- `Channel::Voice` model con `provider: :asterisk`
- `Call.provider` enum con `asterisk`
- Timezone `America/Bogota` en config
- i18n `VOICE_TELEPHONY` en `en.yml`

### ✅ Lane B — Backend Ruby
- `Sip::CredentialService` — devuelve extensión + password + wss_url + sip_domain desde ENV
- `Sip::InternalController` — endpoints `GET /sip/credential` (auth de sesión) + `POST /sip/events` (token de VPS-2) + `GET /sip/routing`
- `Sip::CallRoutingService` — pipeline principal de routing
- `Sip::RoutingDecisionService` — árbol de decisión (assigned/ivr/voicemail/busy)
- `Sip::IvrRoutingService` — dígito IVR → Team
- `Sip::PresenceService` — contador `sip_active_contacts` (multi-dispositivo; increment en register, decrement en unregister)
- `Sip::StatusUpdateService` — mapeo de eventos ARI a estados Chatwoot
- `Voice::TimelineMirrorService` — activity message en conversación WhatsApp cuando finaliza llamada (opción B)
- `Voice::Provider::Asterisk::Adapter`
- Tests spec en `Sip::InternalController`

**⚠️ Lane B NO wired a Asterisk aún:** El Stasis app (Node en VPS-2) que hace los POST/GET a Rails NO existe todavía. Los endpoints Rails están implementados pero nunca han recibido una llamada real de Asterisk.

### ✅ Lane C — Frontend Vue 3
- `useJsSipSession.js` — composable singleton: UA JsSIP, register/unregister, startCall, manejo de sesión, streams
- `useCallSession.js` — delega a JsSIP para provider asterisk
- `CallsPage.vue` — página `/calls` con tabs Marcar / Directorio / Recientes + Reconectar SIP
- `SipCallPanel.vue` — panel lateral softphone (estado SIP, dial, llamada activa)
- `FloatingCallWidget` — widget flotante para llamada activa visible en toda la app
- `VoiceCallButton` — botón saliente en conversación
- `CallCard` — controles Hold + Transfer (solo asterisk)
- Pestaña "Llamadas" en sidebar (visible solo a usuarios con `sip_extension`)
- Auto-register JsSIP al login
- i18n EN + ES completos en `voiceTelephony.json`
- Botón "Reconectar SIP" (unregister → 800ms → register) para forzar re-binding en Asterisk

### ❌ Lane D — Stasis app + infraestructura
- `deploy/asterisk-stasis/` (app Node con ARI) — **NO existe**
- `deploy/coturn/` — **NO existe** (TURN server para NAT traversal en llamadas reales)
- Configuración FreePBX de troncal Claro — **pendiente**
- Contextos del dialplan para routing PSTN — **pendientes**

### ❌ Settings UI
- Wizard de creación de canal de Voz — NO existe
- Tab "Voz/Telefonía" en admin — NO existe

---

## Qué funciona HOY (probado en browser)

| Feature | Estado |
|---------|--------|
| Registro SIP 9001 y 9002 via WebSocket | ✅ Avail |
| Llamada browser → browser (9001↔9002) | ✅ Funciona |
| Línea ocupada al llamarse a sí mismo | ✅ |
| Reconectar SIP (unregister→register) | ✅ |
| FloatingCallWidget, panel softphone | ✅ |
| Llamadas PSTN reales (Claro) | ❌ Stasis app no existe |
| Routing automático entrante | ❌ Stasis app no existe |
| Presencia real en producción | ❌ No hay extensiones en prod aún |

---

## Problema crítico resuelto en la última sesión

### 488 Not Acceptable Here / Incompatible SDP

Después de cada "Apply Config" de FreePBX, las llamadas fallaban con `488 Not Acceptable Here`. El browser enviaba SDP con perfil `UDP/TLS/RTP/SAVPF` (WebRTC) pero Asterisk lo rechazaba.

**Causa:** FreePBX 17 tiene "Enable WebRTC defaults = yes" pero NO activa `ice_support` ni `use_avpf`. El shorthand `webrtc=yes` en PJSIP activaría ambos, pero FreePBX genera parámetros individuales y omite estos dos.

**Fix permanente:** `/etc/asterisk/pjsip.endpoint_custom_post.conf` en VPS-2:

```ini
[9001](+)
ice_support=yes
use_avpf=yes

[9002](+)
ice_support=yes
use_avpf=yes
```

Este archivo se incluye DESPUÉS de `pjsip.endpoint.conf` en la cadena de includes, por eso la sintaxis `(+)` funciona. **Después de cada Apply Config de FreePBX hay que correr:**
```bash
asterisk -rx "module reload res_pjsip.so"
```

**⚠️ IMPORTANTE para nuevas extensiones:** Cada extensión WebRTC que se cree en FreePBX necesita su sección en este archivo.

### 503 Q.850;cause=34 — PJSIP_ETPNOTSUITABLE

Anteriormente 9001 tenía `transport=0.0.0.0-udp`. El browser se registra via WebSocket pero Asterisk intentaba enviar OPTIONS/INVITE via UDP → incompatible → 503.

**Fix:** En FreePBX → Extensions → 9001 → Advanced → Transport → vacío/auto.

---

## Archivos clave del proyecto

```
app/javascript/dashboard/
  composables/
    useJsSipSession.js          ← UA JsSIP singleton, register/unregister, startCall
    useCallSession.js           ← delega a JsSIP para asterisk
    useCallActions.js           ← activeCall, formattedCallDuration, endCall
  routes/dashboard/calls/
    CallsPage.vue               ← /calls page con tabs + botón Reconectar SIP
  components/
    SipCallPanel.vue            ← panel softphone lateral
    FloatingCallWidget/         ← widget llamada activa
  i18n/locale/en/voiceTelephony.json
  i18n/locale/es/voiceTelephony.json

app/models/
  sip_identity.rb
  channel/voice.rb

app/controllers/sip/
  internal_controller.rb        ← /sip/credential, /sip/events, /sip/routing

app/services/
  sip/credential_service.rb
  sip/call_routing_service.rb
  sip/routing_decision_service.rb
  sip/ivr_routing_service.rb
  sip/presence_service.rb
  sip/status_update_service.rb
  voice/timeline_mirror_service.rb
  voice/provider/asterisk/adapter.rb

db/migrate/
  *_create_sip_identities.rb
  *_recreate_channel_voice.rb

docs/plans/
  asterisk-softphone-web-v1.md  ← plan completo (leer antes de tocar VoIP)
```

---

## Variables de entorno requeridas (VPS-1)

```
SIP_WSS_URL=wss://freebpx.procol-proyectoscol.com:8089/ws
SIP_DOMAIN=freebpx.procol-proyectoscol.com
SIP_INTERNAL_TOKEN=<token-secreto>   ← lo usa Stasis app para POST /sip/events
```

---

## Próximos pasos (en orden)

1. **Lane D — Stasis app** (`deploy/asterisk-stasis/`): app Node con ARI (Asterisk REST Interface) que:
   - Intercepta llamadas entrantes en Stasis
   - GET `/sip/routing` a Rails para saber a quién marcar
   - Dial extensión del asesor
   - POST `/sip/events` a Rails con eventos (answered, ended, dtmf)
   - Maneja IVR (colecta dígito → nueva decisión de routing)

2. **coturn** (`deploy/coturn/`): TURN server en VPS-2 para NAT traversal en producción.

3. **Troncal Claro en FreePBX**: configurar trunk SIP con IP auth + codecs alaw/opus.

4. **Settings UI**: wizard para crear Canal de Voz desde el admin de Chatwoot.

5. **Extensiones en producción**: asignar `sip_extension` a asesores reales en la BD.

---

## Reglas del repo (CRÍTICAS)

- Siempre trabajar en rama `custom`
- No commit en `main` nunca
- Tailwind only — no CSS custom
- Vue 3 Composition API con `<script setup>`
- Conventional Commits: `feat(voip):`, `fix(voip):`
- No escribir specs a menos que se pida explícitamente
- Solo actualizar `en.yml` y `en.json` para i18n (nunca otros idiomas directamente)
- Deploy: commit → push → GitHub Actions construye imagen → Redeploy manual en EasyPanel

---

## Commits VoIP en rama `custom` (cronológico inverso)

```
ac73ce2b4  feat(voip): botón Reconectar SIP y traducciones de fallo
ef9acecc8  feat(voip): página dedicada de llamadas + UX improvements
4c0bfb33b  fix(voip): limpiar store al colgar sin requerir callSid===session.id
dd1643471  feat(voip): i18n español VOICE_TELEPHONY + fix allowed_ip? fail-closed
0a9696c97  fix(voip): hardening post-review — 7 bugs corregidos
c1d92251c  feat(voip): fix ICE delay, hangup burbuja y ciclo de vida de sesión SIP
2a94b4ed7  test(voip): spec Sip::InternalController - token + idempotencia
67649aaab  refactor(voip): wss_url/sip_domain desde ENV en CredentialService
9ee678958  fix(voip): usar axios global con headers de auth para /sip/credential
867fe1d7e  feat(voip): cablear llamada entrante JsSIP al callsStore (Cat 1)
8ff81402c  feat(voip): exponer sip_extension en payload del current user (Cat 1)
6a47a1bec  feat(voip): Lane C - Dashboard monta SipCallPanel + register JsSIP al login
c4ef409cb  feat(voip): Lane C - SipCallPanel softphone (panel lateral)
b190357c8  feat(voip): Lane C - CallCard Hold + Transfer asterisk-only
b3b6c8e6b  feat(voip): Lane C - VoiceCallButton rama saliente asterisk
16736ff00  feat(voip): Lane C - calls.js teardown asterisk libera el mic (FIX-6)
1c5871671  feat(voip): Lane C - useCallSession delega a useJsSipSession (FIX-6)
5c0900075  feat(voip): Lane C - helper/inbox.js reconoce provider asterisk (FIX-6)
988b18770  feat(voip): Lane C - useJsSipSession composable (provider asterisk)
67d8c0dc4  feat(voip): Lane C - endpoint GET /sip/credential (session-auth)
e14a14c63  chore(voip): add jssip dependency para softphone WebRTC (Lane C)
2b7ee2a2b  feat(voip): Lane B - Sip::InternalController + rutas /sip/*
0e3d98301  feat(voip): Lane B - modelo Channel::Voice
806484453  feat(voip): Lane B - Voice::TimelineMirrorService (timeline opción B)
f03a20b7e  feat(voip): Lane B - Sip::CredentialService (secret estático v1)
65884b115  feat(voip): Lane B - Voice::Provider::Asterisk::Adapter
158ca3062  feat(voip): Lane B - Sip::StatusUpdateService
277520355  feat(voip): Lane B - Sip::PresenceService (multi-dispositivo)
9a2a4eab5  feat(voip): Lane B - Sip::IvrRoutingService (dígito IVR → Team)
ee0d0d187  feat(voip): Lane B - SharedNumberRule
ddeb6d20b  feat(voip): Lane B - last_rung_at para round-robin atómico
76e484a93  feat(voip): Lane B - Sip::RoutingDecisionService + pipeline de reglas
9fcfbab0f  feat(voip): Lane B - Sip::CallRoutingService
29d8ee297  feat(voip): Lane A items 3-5 - enum asterisk, i18n, timezone Bogota
c570c99dd  feat(voip): Lane A item 2 - Channel::Voice model
0bafb654b  feat(voip): Lane A item 1 - sip_identities migration + SipIdentity model
```

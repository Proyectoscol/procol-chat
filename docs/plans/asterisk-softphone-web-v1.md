# Plan ejecutable — Softphone WebRTC (Asterisk) · Web v1

> Fork ProCol Chat (Chatwoot). Rama `custom`. Revisado: CEO + Eng + Design + DevEx + **voz externa (subagente independiente)**.
> Principio rector: **Asterisk = tercer `provider` de voz** sobre la abstracción existente. No reinventa. No rompe Twilio ni WhatsApp (cambios aditivos).
> ⚠️ Este plan se corrigió tras una revisión independiente que encontró 3 gaps críticos (ver §11). Ya están resueltos abajo.

## 0. Arquitectura

```
        VPS-1 (EasyPanel)                          VPS-2 (Hostinger)
  ┌──────────────────────────────┐         ┌──────────────────────────────┐
  │ Rails (Puma)                 │         │ FreePBX / Asterisk           │
  │  GET  /sip/routing   ◀── HTTPS stateless ──┤ dialplan → Stasis app    │
  │  POST /sip/events    ◀── HTTPS ─────────┼──┤ (Node, deploy/asterisk-  │
  │  GET  /sip/credential◀── (token efímero)│  │  stasis/, fuera de Rails)│
  │  Voice::InboundCallBuilder   │         │  - pide routing a Rails      │
  │  Voice::CallStatus::Manager  │         │  - Dial extensión / IVR      │
  │  AutoAssignment::*RoundRobin │         │  - blind transfer (REFER)    │
  │  Sip::PresenceService        │◀── register/unregister (AMI/Stasis)    │
  │  ActionCable → navegador     │         │  coturn (TURN/NAT, deploy/coturn/)│
  └───────────────┬──────────────┘         └──────────────────────────────┘
                  │ WSS push
                  ▼
        ┌──────────────────────────┐
        │ Navegador asesor         │◀═ SIP/WSS:8089 (señalización) ═ chan_pjsip (webrtc=yes)
        │ JsSIP + SipCallPanel     │◀═ DTLS-SRTP (media) ═════════ coturn
        │ FloatingCallWidget+CallCard (llamada activa, todos los providers)│
        └──────────────────────────┘
```

- **FreePBX** = plano de control (extensiones SIP WebRTC, trunks, audios IVR, guardrails de salida).
- **App Stasis** (Node, `deploy/asterisk-stasis/`, corre en VPS-2) = cerebro de routing; fallback local si Rails no responde.
- **coturn** (`deploy/coturn/`) en VPS-2 desde el inicio.
- **Rails** = datos + decisiones + push; request/response, sin sockets long-lived.

## 1. Reglas de negocio

| Regla | Decisión |
|---|---|
| Routing entrante | Contacto con asesor asignado → suena solo a él. Si no → IVR. |
| Dimensión de routing | **Teams de Chatwoot** (no columna `city`). IVR mapea dígito→Team. |
| Selección de asesor | `IvrRoutingService` calcula `allowed_agent_ids = (Team) ∩ (inbox de Voz) ∩ (sip_active_contacts > 0) ∩ (Chatwoot-disponible) − (Call.active)` y los pasa a `AutoAssignment::InboxRoundRobinService#available_agent(allowed_agent_ids:)`. |
| **Presencia multi-dispositivo (FIX-3 + AREA1-G4 + multi-device)** | `Sip::PresenceService` lleva un **contador** `sip_active_contacts`: register → `INCREMENT`; unregister → `DECREMENT` (piso 0). Disponible si `> 0`. `sip_last_registered_at` se setea en 0→1; `sip_absence_alerted_at` se resetea al volver a 1. Se combina con availability de Chatwoot (`OnlineStatusTracker`, excluye busy/offline). 'Busy' detiene llamadas. |
| **Reconciliación (AREA1-G1)** | La Stasis app, al arrancar, hace `POST /sip/events {type:'sync', registered:[{ext,count}...]}` → `PresenceService` reconcilia `sip_active_contacts` al nº real de contactos PJSIP. `qualify_frequency` mantiene la verdad. |
| **Asignación (FIX-4)** | El RR elige a quién SUENA (efímero). La conversación se asigna en el evento ARI `answered`, **no antes**. Si no contesta → siguiente del RR, sin pegar la conversación. |
| Sin asesor disponible | Buzón/callback + crea conversación (cero llamada perdida silenciosa). |
| Un contacto = un asesor | `InboundCallBuilder` find-or-create atómico + asignación en `answered`. |
| **Visualización (opción B)** | Doble vista: (1) **inbox de Voz puro** = la burbuja `voice_call` viva, reuso 100% de `CallMessageBuilder` (`provider: :asterisk`); (2) **timeline unificado** = un **activity inmutable** ("📞 Llamada · estado · duración · ver") escrito **una vez al estado terminal** en la conversación abierta del contacto en otro inbox (WhatsApp), vía `message_type: :activity` (`activity_message_handler.rb:90`). Si no hay conversación abierta en otro inbox, no se crea el espejo (degrada limpio). Sin sync en el tiempo: la burbuja viva solo vive en Voz. |
| Salientes | Sí, guardrails en FreePBX (allowlist Colombia, tope/extensión, alerta de gasto). |
| Transferencia | Ciega, asesor→asesor del mismo Team (REFER vía ARI `channels/{id}/redirect`). |
| Quién está incluido | `inbox_members` del canal de Voz. Solo ellos ven botón Llamar + panel softphone. |
| **Credenciales (FIX-11 → U2)** | **v1: secret estático** por extensión (en `sip_identities.sip_password`, encriptado), entregado al navegador para el REGISTER (visible en DevTools al propio asesor; riesgo acotado). **Efímero/PJSIP-realtime → fase 2** (evita setup avanzado de Asterisk ahora). |
| Normalización (FIX-8) | **Antes** de pasar el número al builder, `CallRoutingService` lo normaliza a E164 (`Whatsapp::PhoneNumberNormalizationService`). Evita fork de contacto. |
| Identidad de llamada (FIX-10) | `provider_call_id` = **`Linkedid`** de ARI (estable durante toda la llamada y el transfer), no el `Channel id`. |

## 2. Modelo de datos

> **AREA-3 (revisado):** NO se tocan columnas de `users`. El patrón enterprise del repo es tablas separadas (Call, Company, SLA…) y un `add_column :users` generaría conflicto en cada rebase sobre upstream. Se usa una tabla propia del fork.

```
db/migrate/XXXX_create_sip_identities.rb             (tabla propia del fork, AISLADA del rebase)
  sip_identities:
    account_id (FK)                  ← MULTI-CLIENTE (DEX-2): la identidad SIP es POR cuenta
    user_id (FK a users)
    sip_extension (string)
    UNIQUE (account_id, sip_extension)  ← dos clientes pueden reusar '1001' sin chocar
    UNIQUE (account_id, user_id)        ← un asesor, una identidad por cuenta
    sip_password (string, encrypts)  ← v1: estático (U2); efímero/realtime → fase 2
    sip_active_contacts (integer, default 0)  ← MULTI-DISPOSITIVO: nº de registros SIP activos
                                                (PC+Android+tablet). Disponible si > 0. Reemplaza sip_online.
    sip_last_registered_at (datetime)  ← se setea solo en la transición 0→1 (primer dispositivo)
    sip_absence_alerted_at (datetime)  ← se resetea al volver a 1 tras estar en 0 (dedup de alertas)
    sip_absence_mode (boolean, default false)  ← toggle admin "marcar ausente / redirigir" (R3-3 Caso C)
    sip_fcm_token (string, nullable)          ← FASE 2 Android (FCM); nullable, no bloquea Lane A
    sip_apns_voip_token (string, nullable)    ← FASE 2 iOS (APNs PushKit/CallKit)
    sip_push_token_updated_at (datetime, nullable)
    created_at, updated_at
  Nota multi-dispositivo: con varios celulares por asesor, fase 2 podría requerir una tabla
  sip_devices (sip_identity_id, platform, push_token); por ahora basta el contador + tokens nullable.
  (NO city — routing por Team) (NO round_robin_index — reusa motor) (NO sip_fcm_token — Android fase 2)
  Modelo SipIdentity belongs_to :user; User has_one :sip_identity (en overlay enterprise).
  Supuesto single-account documentado (FIX-12).

db/migrate/XXXX_create_channel_voice.rb              (NUEVO Channel, patrón Channel::TwilioSms)
  channel_voice:
    phone_number (string)        ← DID principal del trunk; alimenta Call#from_number/to_number (FIX-1)
    config jsonb:
      ari_host, wss_host, trunk_name
      ivr_digit_to_team { "1"=>team_id, "2"=>team_id }
      shared_numbers []          ← conmutadores: saltan match de contacto → IVR (R3-1)
      max_queue_size (default 10) ← cola máx; si se supera → rechazo + conversación (R4-2)
      staging (boolean, default false) ← inbox de pruebas; su routing nunca entra al RR de prod (R4-9)
      absence_threshold_days (default 2) ← umbral de ausencia, tunable por cliente (DEX-3)
      enable_callback (boolean, default true) ← on/off del callback ocupado/perdida (DEX-3)
    voice_enabled? / has_voice?  ← para isVoiceCallEnabled del FE
  crea su Inbox; inbox_members = asesores incluidos. working_hours del inbox + America/Bogota (R4-1/R4-4).

enterprise/app/models/call.rb                        (solo modelo)
  enum provider: { twilio:0, whatsapp:1, asterisk:2 }   ← aditivo
  (Call#from_number/to_number ya funcionan: Channel::Voice responde a phone_number, FIX-1)
```

## 3. Backend Rails

| Archivo | Tipo | Hace |
|---|---|---|
| `enterprise/app/models/channel/voice.rb` | NUEVO | Channel con `phone_number`, `config`, `initiate_call` que devuelve `{requires_agent_join:false, call_sid:linkedid}` **sin** conference_sid (FIX-5). |
| `enterprise/app/services/sip/call_routing_service.rb` | NUEVO | Normaliza E164 (FIX-8) → `{extension, agent}` si contacto asignado; si no `{ivr:true}`. Lookup indexado. |
| `enterprise/app/services/sip/ivr_routing_service.rb` | NUEVO | dígito→Team → `allowed_agent_ids = Team ∩ inbox Voz ∩ sip_online ∩ Chatwoot-online` (AREA1-G4) → `InboxRoundRobinService#available_agent(allowed_agent_ids:)` → crea contacto+conversación (asigna en `answered`, FIX-4). |
| `enterprise/app/services/sip/presence_service.rb` | NUEVO | register/unregister → `INCREMENT`/`DECREMENT` de `sip_active_contacts` (piso 0, multi-dispositivo); maneja `sip_last_registered_at` (0→1) y reset de `sip_absence_alerted_at`. Fuente de verdad de presencia (FIX-3). |
| `enterprise/app/services/voice/timeline_mirror_service.rb` | NUEVO | Al estado terminal de la llamada, busca la conversación abierta del contacto en otro inbox y crea un **activity inmutable** que la enlaza (opción B). No-op si no hay conversación. Reusa `message_type: :activity`. |
| `enterprise/app/services/sip/status_update_service.rb` | NUEVO | `ASTERISK_STATUS_MAP` (FIX-9, ver abajo) → `Voice::CallStatus::Manager` (intacto). Filtra `provider: :asterisk`. |
| `enterprise/app/services/sip/credential_service.rb` | NUEVO | Emite credencial SIP efímera de sesión, la registra en Asterisk (realtime/ARI), TTL + invalidación en logout (FIX-11). |
| `enterprise/app/services/voice/provider/asterisk/adapter.rb` | NUEVO | `Voice::Provider::Asterisk::Adapter` (nombre correcto, FIX-5): `initiate_call`, `blind_transfer` (REFER ARI), `hangup`. Sin baggage conference. |
| `enterprise/app/controllers/sip/internal_controller.rb` | NUEVO | `GET /sip/routing`, `POST /sip/events`, `GET /sip/credential`. |
| `config/routes.rb` | MOD | rutas `/sip/*`. |
| `config/locales/en.yml` | MOD | `conversations.messages.voice_call.asterisk` (FIX-7, lo usa `CallMessageBuilder`). |

**`ASTERISK_STATUS_MAP` (FIX-9, la pieza de mayor riesgo silencioso):**
```
ARI event / state          → Call status
StasisStart / Ring          → ringing
ChannelStateChange "Up"     → in_progress  (dispara asignación de conversación, FIX-4)
ChannelDestroyed cause=16   → completed    (normal clearing)
ChannelDestroyed cause=17   → no_answer    (busy) / cause=19 (no answer) / cause=21 (rejected)
ChannelDestroyed otros      → failed
```

**Seguridad de `/sip/*`** (el POST crea datos → token = integridad):
1. Token header + `ActiveSupport::SecurityUtils.secure_compare` (constant-time).
2. CSRF-exempt (server-to-server, como `Twilio::VoiceController`).
3. `Rack::Attack` throttle por IP+token.
4. IP allowlist del VPS-2 en el reverse proxy (EasyPanel).
5. Replay idempotente por UNIQUE `(provider, provider_call_id=Linkedid)` (FIX-10).
6. `GET /sip/credential` va por auth de sesión normal (no token), entrega credencial efímera.

## 4. Frontend Vue (Approach C) — superficie completa (FIX-6)

`useJsSipSession.js` es **hermano de `useWhatsappCallSession`**: un provider-session que `useCallSession` delega. NO un sistema paralelo.

| Archivo | Tipo | Nota |
|---|---|---|
| `composables/useJsSipSession.js` | NUEVO | UA JsSIP, pide credencial efímera (`/sip/credential`) y registra al login si es inbox-member de Voz; ciclo completo; notificaciones nativas. |
| `composables/useCallSession.js` | **MOD (FIX-6)** | Convertir `isWhatsappCall ? ... : twilio` en `switch(provider)` de 3 ramas. `joinCall`/`endCall`/`rejectIncomingCall` (líneas 90-214) ganan rama `asterisk` que delega a `useJsSipSession` (sin `TwilioVoiceClient`/`leaveConference`). |
| `helper/inbox.js` | **MOD (FIX-6)** | `VOICE_CALL_PROVIDERS.ASTERISK`; `getVoiceCallProvider` mapea `INBOX_TYPES.VOICE → asterisk`; `isVoiceCallEnabled` reconoce Channel::Voice. |
| `components-next/Contacts/VoiceCallButton.vue` | **MOD (FIX-6)** | `startCall` (línea 148) gana rama Asterisk saliente (JsSIP invite vía `useJsSipSession`), no el `else` Twilio. El botón ya renderiza/branchea — solo se añade la rama. |
| `components-next/call/CallCard.vue` | MOD | Botones **Hold** y **Transferir** visibles solo `provider==='asterisk'`. Transferir → popover lista densa de asesores disponibles del Team. |
| `components-next/call/FloatingCallWidget.vue` | (sin cambio funcional) | Sigue dueño de la llamada activa para todos los providers. |
| `stores/calls.js` | MOD | `teardownByProvider` + `VOICE_CALL_PROVIDERS` ganan rama `asterisk` → `useJsSipSession().hangup()` (o el mic queda abierto). |
| `routes/dashboard/Dashboard.vue` | MOD | montar `SipCallPanel` solo si el usuario es inbox-member de Voz. |
| `components-next/call/SipCallPanel.vue` | NUEVO | Consola: header estado SIP (icono+texto+color), tabs Marcar/Directorio/Recientes, dialpad DTMF doble uso. No duplica la llamada activa. |
| Settings → Canales | MOD | nuevo tipo "Voz (Asterisk)": config conexión + mapeo IVR dígito→Team + crear bandeja + añadir agentes. |
| `contacts/pages/ContactsIndex.vue` | MOD | añadir `VoiceCallButton` a las acciones de fila (se auto-renderiza si hay inbox de voz + teléfono, `VoiceCallButton.vue:55`). |
| `Contacts/ContactsDetailsLayout.vue` (:103) y `conversation/contact/ContactInfo.vue` (:308) | (sin cambio) | **Ya tienen** `VoiceCallButton`; funcionan con Asterisk vía la rama `asterisk` + `isVoiceCallEnabled` (FIX-6). |
| `config/locales/en.json` | MOD | strings del panel + `voice_call.asterisk`. |

Diseño (anclado a `CallCard.vue`/tokens `n-*`): estados loading/empty/error por zona; permiso de notificación contextual al registrar SIP; anti-slop (lista densa, teclado funcional, 44px); desktop-only web v1; color-independiente.

## 5. Orden de build (worktrees)
```
Lane A (fundación, primero): migración users + Channel::Voice + enum asterisk + en.yml/en.json keys
Lane B (backend, ‖ con C):   sip/* services, adapter, credential_service, endpoints, routes
Lane C (frontend, ‖ con B):  useJsSipSession, useCallSession MOD, helper/inbox MOD, VoiceCallButton MOD,
                             SipCallPanel, CallCard ext, calls.js, Dashboard, settings UI
Lane D (fuera de Rails, ‖):  deploy/asterisk-stasis (Node), deploy/freepbx, deploy/coturn (en VPS-2)
B y C no comparten módulos → sin conflicto de merge.
```

## 6. Tests (convención del fork: specs opt-in; aquí los críticos)
- `Sip::IvrRoutingService` — concurrencia (dos llamadas mismo Team), allowed_agent_ids correcto, sin asesor → buzón.
- `Sip::CallRoutingService` — normalización E164, contacto asignado vs IVR.
- `Sip::InternalController` — auth token válido/inválido, replay idempotente por Linkedid.
- `Sip::StatusUpdateService` — cada estado del ASTERISK_STATUS_MAP, no_answer vs completed por cause.

## 7. Failure modes (revisados)
| Codepath | Fallo | Rescate | Asesor ve |
|---|---|---|---|
| Stasis→Rails /sip/routing | timeout/Rails down | fallback local Stasis → IVR/cola | entra por IVR |
| IvrRoutingService | sin asesor sip_online en Team | buzón/callback + crea conversación | mensaje |
| RR elige agente que no contesta | timeout Dial | Stasis avanza al siguiente; conversación NO asignada aún (FIX-4) | suena al siguiente |
| sip_online desincronizado | unregister no llegó | TTL/heartbeat de presencia; Stasis Dial con timeout corto cae al siguiente | siguiente |
| JsSIP register | credencial efímera vencida/WSS down | re-pedir credencial; badge rojo + ⟳ Reconectar | "Desconectado" |
| ActionCable push | socket down | degrada (llamada entra igual) | panel tarda |
| teardown asterisk | doble colgar | idempotente | nada |

## 8. NOT in scope
App Android + FCM (fase 2) · Transferencia atendida (fase 2) · Auto-provisión FreePBX API (fase 2) · Grabación/reporting/wallboard · Panel móvil · Multi-cuenta (single-account asumido) · App Stasis/coturn/FreePBX se despliegan en VPS-2 (esqueletos en `deploy/`).

## 9. Despliegue
- Migraciones aditivas/reversibles. Enum solo modelo.
- ENV: `ASTERISK_ROUTING_SECRET`, `ASTERISK_ARI_URL/USER/PASSWORD`, `SIP_WSS_HOST/PORT`, `VOICE_CALL_STUN_URLS` (existe), `VOICE_CALL_TURN_URLS/USER/SECRET`, `SIP_CREDENTIAL_TTL`.
- Flujo: commit `custom` → push → GitHub Actions build → Redeploy manual EasyPanel.

## 10. Entregables fuera del repo Rails (esqueletos en `deploy/`)
- `deploy/asterisk-stasis/` — app Node ARI: StasisStart → routing → Dial/IVR/transfer, presencia register/unregister → Rails, fallback local.
- `deploy/freepbx/` — pjsip WebRTC extension template, inbound route → custom destination (Stasis), trunk, outbound route restrictions (toll fraud), IVR module.
- `deploy/coturn/` — `turnserver.conf` con TLS + auth.

## 11. Correcciones tras la voz externa (honestidad)
La revisión independiente encontró que el "0 critical gaps" previo era incorrecto. Críticos hallados y **resueltos** en este plan:
1. **Call#from_number/to_number sin phone_number** → `Channel::Voice.phone_number` (DID). 
2. **Round-robin por inbox, no por Team** → `IvrRoutingService` construye `allowed_agent_ids` por Team.
3. **Verdad de presencia (online dashboard ≠ registro SIP)** → `sip_online` ascendido a fuente de verdad vía `PresenceService` (FIX-3).
Altos resueltos: asignación en `answered` (FIX-4), adapter nombre+contrato (FIX-5), superficie frontend completa (FIX-6), secret efímero (FIX-11). Medios: i18n (FIX-7), normalización E164 (FIX-8), ASTERISK_STATUS_MAP (FIX-9), Linkedid (FIX-10).

## 12. Validación especializada — 3 áreas (revisado contra código + specs Claro)

**AREA 1 — Sincronización de estado (Chatwoot/Asterisk/FreePBX):**
- G1 MEDIO (drift de presencia) → reconciliación por sync de arranque de la Stasis app + `qualify_frequency`.
- G2 MEDIO (extensión deshabilitada vs `sip_online=true`) → mitigado por Dial-timeout + sync de G1.
- G4 ALTO (busy/offline de Chatwoot no detenía llamadas) → routing = `sip_online ∩ Chatwoot-online`.
- NO-gap: resolver conversación NO toca llamadas (`removeCallsForConversation` no se invoca; verificado).
- G5 BAJO: inbox-member removido sale del RR (`inbox_member.rb:31`); extensión sigue registrable.

**AREA 2 — Trunk Claro Colombia (specs verificadas):**
- A2-1 ALTO: Claro = **G.711A (alaw)**, no ulaw. WebRTC = opus → **transcoding alaw↔opus**. `allow=opus,alaw,ulaw`; dimensionar CPU VPS-2.
- A2-2 ALTO: Claro **autentica por IP fija, sin REGISTER**. pjsip trunk `type=identify`; VPS-2 con **IP pública estática** whitelisteada.
- A2-3 MEDIO: formato CallerID por confirmar con Claro (`normalizeE164` cubre casos comunes).
- A2-4 MEDIO: Claro puede entregar por **red privada** (doble NIC/rutas) → **confirmar antes de aprovisionar VPS-2**.
- A2-5 MEDIO: DTMF cruzando transcode → `dtmf_mode=rfc4733`, probar IVR end-to-end.
- coturn: **sin config especial** para Claro (TURN es solo lado asesor; el trunk es servidor-a-servidor).

**AREA 3 — Storage SIP:** tabla `sip_identities` (FK a users), NO columnas en `users` ni `custom_attributes`. Razón decisiva: patrón enterprise = tablas separadas + aislamiento del rebase sobre upstream.

### Acciones de verificación con Claro (antes de aprovisionar VPS-2)
- [ ] Confirmar formato exacto del header `From` (con/sin 57, con/sin +).
- [ ] Confirmar entrega: SIP por internet público (IP estática) vs circuito privado.
- [ ] Confirmar IP(s) del SBC de Claro a whitelistear y la IP pública estática del VPS-2.

## 13. UI de administración + Unknown-unknowns + Checklist pre-Lane-A

### 13.1 UI de admin (AREA 1) — mínimo operable sin tocar BD
| Pieza | Reuso / Nuevo | Decisión |
|---|---|---|
| Pools de ciudades | **Reuso total**: `settings/teams/` (Teams ya tienen admin) | — |
| Asignar `sip_extension` + ver estado SIP en vivo | **NUEVO**: pestaña Settings **"Voz / Telefonía"** | tabla de asesores con extensión (asignar/editar) + badge `sip_online` (ActionCable) + overview routing |
| Crear inbox de Voz | **NUEVO wizard**: entrada en `ChannelList.vue:25` + `ChannelFactory` + componente creación | `Channel::Voice` no estaba en el selector (era toggle Twilio) |
| Config DID + IVR dígito→Team | **Clonar** `VoiceConfigurationPage.vue` (hoy Twilio: `api_key_sid`) → `AsteriskVoiceConfigPage` (U7) | el modelo de datos Twilio no aplica |
| Validar extensión existe en FreePBX al asignar | **NUEVO**: el endpoint de asignación consulta ARI antes de guardar (AREA2-paso2 gap) | evita asignar extensiones inexistentes |

### 13.2 Unknown-unknowns (los que bloquean)
- **U1 CRÍTICO (Lane D):** `codec_opus.so` no viene por defecto en Asterisk → sin transcode opus↔alaw = sin audio. Instalar y verificar versión.
- **U2 ALTO (resuelto):** efímero exige PJSIP realtime → **v1 usa secret estático**, efímero a fase 2.
- **U3 ALTO (Lane B+D):** ARI no lista registros PJSIP. La presencia real (register/unregister) es **AMI** (`ContactStatus`/`PeerStatus`), no `DeviceStateChanged` de ARI. La Stasis app necesita **también conexión AMI**. Corregir skeleton.
- **U4 ALTO (Lane D):** la Stasis app debe estar arriba antes de las llamadas → systemd auto-restart + healthcheck + fallback dialplan.
- **U6 ALTO (Lane C+D):** WSS exige cert válido y confiable (no self-signed) o el navegador rechaza el WebSocket.
- **U5/U7/U8/U9 (MEDIO/BAJO):** tormenta de registro 9am; `VoiceConfigurationPage` Twilio-específico (clonar); i18n en `en.yml` Y `en.json`; AMI user en `manager.conf`.

### 13.3 ✅ DEBE estar definido y acordado ANTES del primer commit de Lane A
**Decisiones de modelo/código (cierran el contrato de Lane A):**
- [x] Storage = tabla `sip_identities` (no columnas en `users`).
- [x] `sip_password` estático en v1 (encriptado); efímero a fase 2.
- [x] Routing = `sip_online ∩ Chatwoot-online`; asignación en `answered`.
- [x] Dimensión = Teams; IVR dígito→Team en config del `Channel::Voice`.
- [x] `provider_call_id` = `Linkedid`; enum `provider: { ..., asterisk:2 }`.
- [ ] Nombre final de la tabla/modelo (`sip_identities` / `SipIdentity`) y namespace (¿`enterprise/`?).
- [ ] Keys i18n en `en.yml` + `en.json` (incl. `voice_call.asterisk`).

**Verificaciones externas (no bloquean Lane A en código, sí el funcionamiento real):**
- [ ] Claro: formato del header `From`, tipo de entrega (público/privado), IPs a whitelistear.
- [ ] VPS-2: IP pública estática confirmada.
- [ ] Asterisk: `codec_opus` instalable en la versión elegida (U1).
- [ ] Asterisk: AMI + ARI users planificados (U3/U9).

**UI mínima acordada (define Lane C):**
- [x] Pestaña "Voz / Telefonía" para extensión + estado SIP.
- [ ] Alcance del wizard de creación del inbox de Voz.

> Lane A (migración `sip_identities` + `Channel::Voice` + enum + i18n) puede arrancar en cuanto se cierren los 2 checkboxes de "Decisiones de modelo" pendientes. Las verificaciones con Claro/Asterisk corren en paralelo y bloquean Lane D, no Lane A.

## 14. Endurecimiento — ronda de 4 revisores (asesor / admin / abogado del diablo / auditor)

### 14.1 Reglas de negocio fijadas en esta ronda
- **Horarios (R4-1):** el inbox de Voz usa `working_hours` (existe) en **America/Bogota**. Fuera de horario: mensaje + conversación "llamada fuera de horario" + **notificación al asesor asignado** (no recibe en vivo, sí se entera). Festivos colombianos = config manual del inbox. Sin horario configurado → 24/7 (fallback seguro).
- **Asesor ocupado (R4-3):** cada contacto pertenece a SU asesor. Si el asignado está en `Call.active`, **NO se redirige** a otro: mensaje de ocupado + registro "llamada perdida - asesor ocupado" + **banner en tiempo real** en su panel: "[Cliente] intentó llamarte hace 2 min · [Devolver llamada]". Si el contacto no tiene asignado y todo el Team está ocupado → mismo comportamiento (notifica al que tocaba por round-robin). Aplica también fuera de horario.
- **Asesor ausente (R3-3), escalonado por presencia (`sip_active_contacts=0` desde hace N días):**
  - **Caso A (< 2 días laborables):** "tu asesor te devolverá la llamada" + llamada perdida al asignado + notificación. NO redirige (ausencia corta).
  - **Caso B (> 2 días laborables, detectado por `Sip::AbsenceDetectorJob`):** "te conectamos con un colega" → round-robin del Team de la ciudad del ausente (excluyéndolo) → conversación al nuevo asesor + **notifica al admin** que se aplicó fallback automático.
  - **Caso C (`sip_absence_mode=true`, admin marca vacaciones/incapacidad):** Caso B desde el día 1. Toggle en la pestaña "Voz/Telefonía".
- **Número compartido/conmutador (R3-1):** lista `shared_numbers` en la config del `Channel::Voice`. Esas llamadas **saltan el match de contacto** → directo a IVR/Team.

### 14.2 Componentes nuevos derivados
| Componente | Tipo | Rol |
|---|---|---|
| `Sip::RoutingDecisionService` | NUEVO | Orquesta el árbol: working_hours → shared_numbers → asignado (presente/ocupado/ausente A/B/C) → Team RR → buzón + notificaciones. Encapsula toda la lógica de §14.1. |
| `Sip::AbsenceDetectorJob` | NUEVO (cron diario) | Calcula días laborables desde `last_seen_online_at`; a >2 días notifica admin y habilita fallback (Caso B). |
| `Sip::CallReconciliationJob` | NUEVO (cron) | Cierra Calls huérfanas en `in_progress` sin evento de fin (R3-4, Stasis muere a mitad de llamada). |
| Notificaciones | **Reuso** `notifications` + ActionCable | Banner asesor (callback) + avisos admin (fallback/ausencia). |
| `Channel::Voice.config.shared_numbers` | MOD config | lista de conmutadores. |
| Timezone **America/Bogota** | Config | Rails (`config.time_zone`, hoy UTC), Asterisk y FreePBX consistentes (R4-4). |
| Lock de pestaña única | MOD `useJsSipSession` | Evita el flapping de registro con 2 pestañas (R3-10). |
| Reconexión + re-REGISTER | MOD `useJsSipSession` | Caída de red 30s → reconecta y re-registra + badge "Reconectando" (R1-4). |
| Salud del trunk + alerta "0 entrantes" | NUEVO (admin) | Indicador trunk Claro (AMI) + alerta de ausencia de llamadas (R2-2/R2-3). |

### 14.3 Consolidado de gaps por categoría

**(2) BLOQUEAN el commit de Lane A** (tocan el contrato de schema):
- `sip_identities` con `last_seen_online_at` + `sip_absence_mode` (R3-3) — **definir ahora**.
- `Channel::Voice.config.shared_numbers` + working_hours/festivos del inbox (R3-1/R4-1) — definir el shape del config.
- Timezone **America/Bogota** en Rails (R4-4) — config, pero debe entrar con la fundación.
- (Pendientes previos) nombre/namespace `SipIdentity` en `enterprise/`, keys i18n `en.yml`+`en.json`.

**(3) Se resuelven con CONFIGURACIÓN (no código):**
- Timezone en Asterisk/FreePBX = America/Bogota (R4-4).
- Monitoreo de cert WSS + auto-renovación Let's Encrypt (R3-8).
- Monitoreo de coturn / rango UDP (R3-9, R2-8).
- Ventana de mantenimiento para reiniciar FreePBX (R2-10).
- Festivos colombianos cargados en el inbox (R4-1).
- Backup de `sip_identities`/`calls` en el dump Postgres existente (R4-6).

**(4) Necesitan DECISIÓN DE NEGOCIO tuya (aún abiertas):**
- Máx. llamadas en cola antes de rechazar (R4-2).
- Retención de logs de llamadas — ¿cuánto tiempo? (R4-5).
- **Habeas data (Ley 1581 CO)** — política de tratamiento/consentimiento de grabaciones y registros (R4-7). **Legal.**
- Ambiente de **staging** separado antes de dárselo a asesores reales (R4-9).

**(5) DEUDA TÉCNICA aceptable para v1 (documentada):**
- Contacto con 2 números: el secundario crea contacto separado (R3-2) — Chatwoot no es multi-número nativo.
- Reporting de llamadas perdidas por asesor: v1 filtro manual en inbox de Voz; reporting real → fase 2 (R2-7).
- Crash del navegador a mitad de llamada: el cliente escucha corte (R1-5).
- Credencial estática visible al propio asesor en DevTools (U2) → efímero fase 2.

### 14.4 Lo que se RESOLVIÓ/aclaró en esta ronda (no son gaps)
- RR bajo spike de Postgres: **no aplica**, el RR es Redis (R3-7). Dependencia real = Redis.
- Reiniciar Stasis no corta llamadas activas (viven en el bridge de Asterisk); solo las nuevas caen al fallback (R2-9).
- Retry de mismo call_sid: idempotente por UNIQUE `(provider, Linkedid)` (R3-6).

## 15. Fase 2 — Multi-dispositivo + App móvil (planificada, no vaga)

> Multi-dispositivo afecta **Lane B y D y entra al schema AHORA** (columnas nullable, no bloquea Lane A). La app móvil es construcción de fase 2, pero su arquitectura queda decidida aquí.

### 15.1 Multi-dispositivo (entra ya)
- **Schema:** `sip_active_contacts` (contador) reemplaza `sip_online`; `sip_fcm_token`/`sip_apns_voip_token` nullable (ver §2).
- **Presencia:** register → INCREMENT, unregister → DECREMENT (piso 0); disponible si `> 0` (§1).
- **FreePBX/PJSIP:** `max_contacts=5` por endpoint → PC + Android + tablet registran a la vez con el **mismo `sip_extension`** (anula el lock de pestaña única R3-10 para dispositivos legítimos; el lock pasa a ser solo anti-doble-pestaña-mismo-navegador).
- **Routing:** filtra `sip_active_contacts > 0` (no booleano).
- **UI admin:** la pestaña "Voz/Telefonía" muestra el contador de dispositivos por asesor (derivando online/offline de `> 0`).
- **Ring multi-dispositivo:** al sonar una extensión con varios contactos, Asterisk hace fork a todos los dispositivos registrados; contesta el primero, los demás dejan de sonar (comportamiento PJSIP nativo).

### 15.2 App móvil (fase 2, arquitectura decidida)
- **Stack:** fork de [`chatwoot/chatwoot-mobile-app`](https://github.com/chatwoot/chatwoot-mobile-app) (React Native).
- **Lib SIP:** `react-native-sip2` (wrapper PJSIP, más mantenida que `react-native-pjsip` en 2025).
- **Credenciales:** las **mismas** que el web (mismo `sip_extension`/secret). Login con el **mismo token de Chatwoot**; al loguear, la app registra en Asterisk.

**Notificaciones con app cerrada/background — push platform-specific (decidido):**
> El "permiso de segundo plano" NO sirve: iOS y Android matan los sockets en background. Hay que **despertar por push**.

| Plataforma | Mecanismo | Por qué |
|---|---|---|
| **Android** | FCM **high-priority data message** → despierta la app → **ConnectionService (Telecom)** muestra la llamada full-screen → registra PJSIP → contesta | FCM high-priority despierta apps killed; ConnectionService da UI de llamada nativa en lock screen |
| **iOS** | APNs **VoIP push (PushKit)** → **debe reportar a CallKit de inmediato** → UI nativa de llamada en lock screen → registra PJSIP → contesta | Apple **exige** PushKit→CallKit para VoIP; los data messages de FCM NO despiertan una app iOS killed |

Flujo backend (común): Stasis detecta entrante → Rails busca `sip_fcm_token`/`sip_apns_voip_token` del asesor → dispara FCM (Android) o APNs-VoIP (iOS) high-priority → el dispositivo despierta, registra y recibe la llamada.

**La app de fase 2 necesita:** pantalla de llamada activa nativa, notificación entrante con Contestar/Rechazar en lock screen (CallKit/ConnectionService), `READ_CONTACTS`, el mismo CallHistory y directorio que el web, y funcionar con pantalla apagada (vía push, no socket de fondo).

### 15.3 Web y móvil comparten (un solo backend)
- Las **mismas credenciales SIP** (`sip_extension`/secret).
- El **mismo endpoint de routing** en Rails (`/sip/routing`, `/sip/events`).
- El **mismo `Voice::CallMessageBuilder` y `Voice::TimelineMirrorService`**.
- La **misma tabla `calls`** (modelo `Call`) — *nota: el plan la llama `calls`, no `call_logs`*.
- **Solo difieren en el cliente SIP:** JsSIP (web) vs PJSIP/`react-native-sip2` (móvil).

## 16. Decisiones de negocio resueltas + Schema Lane A cerrado

### 16.1 Las 4 decisiones (resueltas)
- **R4-2 Cola máxima:** `max_queue_size = 10` (parametrizable en config del inbox, §2). Si se supera: mensaje "no podemos atenderte, intenta en unos minutos" + conversación "llamada rechazada por cola llena". Lo aplica `Sip::RoutingDecisionService`.
- **R4-5 Retención:** 2 años en `calls`. `Sip::LogArchiveJob` (cron **mensual**) mueve registros > 2 años a **`calls_archive`** (misma BD, sin borrado físico). El admin consulta el archivo desde la UI. *(El usuario lo llama "call_logs"; la tabla real es `calls`/`Call`.)*
- **R4-7 Habeas data (Ley 1581) — derecho al olvido:** el overlay enterprise añade a `Contact` `has_many :calls, dependent: :destroy_async` (+ callback que limpia también `calls_archive`) → al borrar un contacto se eliminan sus registros de llamadas. **Doc explícita:** el sistema provee el *mecanismo técnico*; la *política de tratamiento/consentimiento* es responsabilidad legal del negocio.
- **R4-9 Staging:** extensiones **9001-9010** reservadas en FreePBX para pruebas. Inbox de Voz aparte con `config.staging = true`. El RR de producción **nunca** incluye extensiones `9xxx`. Misma infra VPS-2, cero costo extra.

### 16.2 Componentes nuevos derivados
| Componente | Tipo | Rol |
|---|---|---|
| `db/migrate/..._create_calls_archive.rb` | NUEVO | tabla espejo de `calls` para archivo (R4-5). |
| `Sip::LogArchiveJob` | NUEVO (cron mensual) | archiva `calls` > 2 años → `calls_archive`. |
| `Contact` overlay (enterprise) | MOD | `has_many :calls, dependent: :destroy_async` + limpieza de archivo (R4-7). |
| Cola/rechazo en `RoutingDecisionService` | MOD | aplica `max_queue_size` (R4-2). |
| Filtro `staging` en routing | MOD | excluye `9xxx` del RR de prod (R4-9). |

### 16.3 ✅ Schema de Lane A — CERRADO
- **Modelo `SipIdentity`** en `enterprise/app/models/sip_identity.rb` (overlay); migración en `db/migrate/`. `belongs_to :account, :user`; `User has_one :sip_identity` (por cuenta) vía overlay enterprise.
- **`sip_identities`** (final, multi-cliente DEX-2): `account_id` (FK), `user_id` (FK), `sip_extension`; **UNIQUE (account_id, sip_extension)** + **UNIQUE (account_id, user_id)**; `sip_password` (encrypts), `sip_active_contacts` (int, 0), `sip_last_registered_at`, `sip_absence_alerted_at`, `sip_absence_mode` (bool, false), `sip_fcm_token` (nullable), `sip_apns_voip_token` (nullable), `sip_push_token_updated_at` (nullable), timestamps.
- **`Channel::Voice`** con `config`: `shared_numbers` (array), `max_queue_size` (10), `staging` (bool), `absence_threshold_days` (2), `enable_callback` (bool) — §2.
- **`Call.provider`** enum: `{ twilio:0, whatsapp:1, asterisk:2 }`.
- **`config.time_zone = 'America/Bogota'`** en `config/application.rb` (Rails hoy UTC).
- **i18n** bajo **`VOICE_TELEPHONY.*`** (`en.json` front) + `conversations.messages.voice_call.asterisk` (`en.yml` back).
- **`calls_archive`** (R4-5) puede entrar en Lane A o como migración aparte (no bloquea).

> Con esto, el contrato de datos de Lane A está completo y acordado. Lane A = migración `sip_identities` + `Channel::Voice` + enum `asterisk` + `time_zone` + keys i18n.

## 17. Extensibilidad y multi-cliente (DevEx — dónde cambiar qué)

> Objetivo: que modificar la lógica de asignación (o cualquier regla) sea fácil y localizado, y que el sistema escale a otros clientes sin reescribir.

### 17.1 Mapa de puntos de extensión ("para cambiar X, edita Y")
| Cambiar… | Archivo único | Tipo |
|---|---|---|
| **Quién recibe una llamada** (asignación completa) | `Sip::RoutingDecisionService` (pipeline, §17.2) | Código aislado |
| Una regla puntual (horario, ocupado, ausencia, cola…) | `Sip::Routing::Rules::<Regla>` (un objeto) | Código local |
| Algoritmo de rotación | `AutoAssignment::InboxRoundRobinService` (reuso core) | Reuso |
| El PBX (Asterisk → otro) | `Voice::Provider::Asterisk::Adapter` (mismo contrato que Twilio) | Adapter |
| Presencia/disponibilidad | `Sip::PresenceService` | Aislado |
| Ciclo de vida de llamada | `InboundCallBuilder` + `CallStatus::Manager` (compartido voz) | Reuso |
| Pools, IVR, conmutadores, cola, horarios, **umbral ausencia, callback on/off** | **Config del `Channel::Voice`** (admin, sin código) | Parametrizado |

### 17.2 RoutingDecisionService = pipeline de reglas nombradas (DEX-1)
`Sip::RoutingDecisionService` corre reglas **en orden**; cada una es un objeto con `call(context) → :handled | :continue`:
```
Sip::Routing::Rules::
  WorkingHoursRule      → fuera de horario: buzón + notifica asignado (R4-1)
  SharedNumberRule      → conmutador: salta match de contacto → IVR (R3-1)
  AssignedAgentRule     → asignado presente/ocupado/ausente A/B/C (R4-3/R3-3)
  TeamRoundRobinRule    → RR del Team (sip_active_contacts>0 ∩ online − Call.active)
  QueueLimitRule        → cola > max_queue_size: rechazo + conversación (R4-2)
  VoicemailFallbackRule → buzón + crea conversación
```
Cambiar/desactivar/reordenar una regla = tocar un archivo chico sin romper las demás. Variar por cliente = otra lista de reglas o tunear su config.

### 17.3 Multi-cliente (DEX-2)
- **Ya escala (nativo de Chatwoot):** Teams, inboxes, canales, working_hours son **por cuenta**. Cada cliente = una cuenta Chatwoot + su `Channel::Voice` + sus Teams + su trunk + su rango de extensiones.
- **Resuelto ahora:** `sip_identities` UNIQUE **por `(account_id, sip_extension)`** → dos clientes pueden usar '1001' sin chocar (§16.3).
- **Pendiente por cliente (config/infra, no código):** namespace de extensiones en Asterisk (un Asterisk por cliente, o rangos separados); `ASTERISK_ROUTING_SECRET` por instancia; el endpoint `/sip/routing` resuelve el `account_id` desde el inbox/extensión.
- **Tunable por cliente sin deploy (DEX-3):** `absence_threshold_days`, `enable_callback`, `max_queue_size`, pools, IVR, horarios — todo en config del inbox.

### 17.4 Qué sigue en código vs config
- **Config (admin, por cliente, sin deploy):** pools/Teams, IVR, conmutadores, cola, horarios, festivos, umbral de ausencia, callback on/off, staging.
- **Código (un dev, raro):** el **orden** del pipeline de reglas, agregar una regla nueva, cambiar el PBX (adapter), el motor de RR.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | CLEAR | HOLD_SCOPE, 4 diferidos |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR | 5 issues |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | CLEAR | 5/10 → 9/10, 8 decisiones |
| DevEx Review | inline | Config/provisioning/routing | 1 | CLEAR | 4 decisiones |
| Outside Voice | subagente Claude | Bug/inconsistency hunt | 1 | resolved | 3 críticos + 8 altos/medios resueltos |
| Especializada | 3 áreas (sync/Claro/migración) | Validación a fondo | 1 | resolved | G4 (presencia x2), trunk Claro (codec/IP), tabla sip_identities |
| Admin/Unknown | UI admin + provisioning + unknown-unknowns | Validación operacional | 1 | resolved | Pestaña Voz, U1 codec_opus, U3 AMI presencia, secret estático v1 |
| Visualización | timeline voz+chat (opción B) | Modelo de datos UI | 1 | resolved | activity inmutable + TimelineMirrorService |
| **4 Revisores** | asesor/admin/abogado/auditor | Endurecimiento exhaustivo | 1 | resolved | Ausencia escalonada, ocupado→callback, horarios, número compartido, sweeper, timezone (ver §14) |
| Multi-device + móvil | arquitectura fase 2 | Planificación no-vaga | 1 | resolved | sip_active_contacts (contador), max_contacts=5, push FCM/PushKit-CallKit, backend compartido (§15) |
| Cierre de negocio | 4 decisiones + schema | Cierre Lane A | 1 | resolved | cola=10, retención 2a+archivo, habeas data (destroy), staging 9xxx; schema CERRADO (§16) |
| DevEx/Extensib. | dónde-cambiar-qué + multi-cliente | Escalabilidad | 1 | resolved | pipeline de reglas (DEX-1), UNIQUE por cuenta (DEX-2), params tunables (DEX-3) — §17 |

- **UNRESOLVED:** 0 — schema de Lane A cerrado (§16.3), 4 decisiones de negocio resueltas (§16.1).
- **ACCIONES ABIERTAS (no bloquean Lane A):** verificaciones Claro/Asterisk (Lane D) + config (cert/coturn/timezone en Asterisk-FreePBX).
- **VERDICT:** ✅ CLEARED — Lane A listo para implementar y commitear.

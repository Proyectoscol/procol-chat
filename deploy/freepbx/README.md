# FreePBX / Asterisk — configuración (VPS-2)

Responde la pregunta: **¿está todo claro y permite personalizar IVR, extensiones, etc.?** Sí. FreePBX es el plano de control; tú defines extensiones, trunks, IVR y rutas desde su UI. Rails solo decide a quién suena. Esto es lo que hay que dejar configurado.

## 1. Extensiones WebRTC (una por asesor)
Cada asesor necesita una extensión PJSIP con WebRTC para registrarse desde el navegador (JsSIP/WSS).
- En FreePBX: **Applications → Extensions → Add (PJSIP)**.
- Marcar **WebRTC = Yes** (auto-configura DTLS, ICE, `transport=ws`, `media_encryption=dtls`, `rtcp_mux=yes`, `use_avpf=yes`).
- Ver plantilla de referencia en `pjsip.webrtc.conf.example`.
- **Personalización total:** agregas/quitas extensiones cuando quieras; el admin mapea agente→extensión en Chatwoot (campo admin-only). Cientos de extensiones, sin tocar código.

### Credenciales efímeras (FIX-11)
El plan usa **credencial de sesión**, no un secret estático. Dos vías:
- **PJSIP Realtime** (recomendado): los `auth` viven en una tabla que Rails escribe (password de sesión con TTL). Asterisk los lee en caliente. El navegador recibe la credencial vía `GET /sip/credential`.
- Alternativa simple v1: password estático por extensión en FreePBX (aceptas que el agente puede verlo en DevTools). Cambiar a realtime cuando el realtime esté listo.

## 2. Trunk SIP — Claro Colombia (specs verificadas)
- **Connectivity → Trunks**: trunk del carrier (DID entrante + salientes).
- El `phone_number` del `Channel::Voice` en Chatwoot = el DID principal de este trunk (FIX-1).
- **Códec (A2-1):** Claro usa **solo G.711, prioridad G.711A (alaw)**. NO G.729 (limita canales a 4). El navegador usa opus → **Asterisk transcodifica alaw↔opus** en cada llamada. Trunk: `allow=alaw,ulaw`. Dimensionar CPU del VPS-2 para el transcoding concurrente (pico ~30-50 llamadas).
- **Autenticación (A2-2):** Claro autentica **por IP fija, SIN REGISTER**. En pjsip: trunk con `type=identify` (match por IP del SBC de Claro), **sin** sección `registration`. El **VPS-2 necesita IP pública estática** que Claro whiteliste.
- **Red de entrega (A2-4):** Claro a veces entrega por **circuito privado** (no internet público) → requeriría doble NIC + rutas estáticas en el VPS. **Confirmar con Claro** antes de aprovisionar el VPS-2.
- **CallerID (A2-3):** confirmar con Claro el formato del header `From` (con/sin `57`, con/sin `+`). `normalizeE164` en la Stasis app cubre los casos comunes.
- **DTMF (A2-5):** `dtmf_mode=rfc4733` en trunk y extensiones; probar la recolección del IVR end-to-end (cruza el transcode).

### Acciones de verificación con Claro (antes de aprovisionar)
- [ ] Formato exacto del `From` entrante.
- [ ] ¿SIP por internet público (IP estática) o circuito privado?
- [ ] IP(s) del SBC de Claro a whitelistear + IP pública estática del VPS-2.

## 3. Ruta entrante → Stasis (el handoff a la app de routing)
- **Connectivity → Inbound Routes**: DID entrante → **Custom Destination**.
- **Admin → Custom Destinations**: destino que entra al contexto Stasis (ver `extensions_custom.conf.example`).
- Resultado: toda llamada entrante cae en la app Stasis (`deploy/asterisk-stasis/`), que consulta a Rails.

## 4. IVR de ciudades/Teams
Dos opciones, tú eliges:
- **A (recomendada, flexible):** el IVR lo maneja la **app Stasis** (playback + getDigit por ARI). El mapeo dígito→Team vive en la config del `Channel::Voice` en Chatwoot, editable desde el frontend. Cambias ciudades/Teams sin tocar FreePBX.
- **B:** usar el **módulo IVR de FreePBX** (Applications → IVR). Más visual, pero cada cambio de menú se hace en FreePBX y hay que mantenerlo en sync con los Teams de Chatwoot.

> El plan asume A: audios subidos a FreePBX (System Recordings), referenciados por nombre desde la Stasis app (`IVR_PROMPT`).

## 5. Guardrails de salida (toll fraud — obligatorio)
- **Connectivity → Outbound Routes**: dial patterns que **solo** permitan destinos Colombia (`+57` / patrones nacionales).
- Límites de llamadas concurrentes/min por extensión (Asterisk `call-limit` o pjsip `device_state_busy_at`).
- Alertas de gasto en el carrier.
- Sin esto, una credencial filtrada = llamadas internacionales reales.

## 6. WSS / certificados
- Habilitar **HTTP/TLS** y **WebSocket** en `http.conf` (puerto 8089, TLS).
- Certificado válido (Let's Encrypt) para `SIP_WSS_HOST`.
- coturn aparte (ver `deploy/coturn/`).

## 7. Códec opus (U1 — CRÍTICO, bloquea audio)
Asterisk **no trae `codec_opus` por defecto**. Sin él no hay transcode opus(navegador)↔alaw(Claro) → **llamadas sin audio**.
- Instalar `codec_opus.so` compatible con la versión de Asterisk del VPS-2 (Sangoma/Asterisk publican binarios).
- Verificar: `asterisk -rx "core show translation"` debe mostrar rutas opus↔alaw.

## 8. AMI para presencia (U3/U9 — bloquea sip_online real)
La presencia SIP verídica (register/unregister) NO sale de ARI, sale de **AMI**.
- Crear un usuario AMI en `manager.conf` (read: `system,call,reporting`) para la Stasis app.
- La Stasis app escucha el evento `ContactStatus` (Reachable/Unreachable) y al arrancar hace `PJSIPShowContacts` para el full-sync (reconciliar `sip_online`).

## Checklist de aprovisionamiento
- [ ] Trunk Claro: `type=identify` por IP, sin REGISTER, `allow=alaw,ulaw` (§2).
- [ ] **`codec_opus` instalado y verificado** (§7, U1) — sin esto no hay audio.
- [ ] `http.conf`: TLS + WS en 8089 con **cert válido y confiable** (no self-signed, U6).
- [ ] Custom Destination + Inbound Route → Stasis (`extensions_custom.conf.example`).
- [ ] **ARI user** (`ari.conf`) para routing + **AMI user** (`manager.conf`) para presencia (§8, U3/U9).
- [ ] Outbound routes restringidas a Colombia + límites por extensión (toll fraud).
- [ ] Audios del IVR subidos (System Recordings).
- [ ] coturn corriendo con TLS+auth (`deploy/coturn/`).
- [ ] Stasis app bajo systemd con auto-restart + healthcheck (U4).
- [ ] **Extensiones 9001-9010 reservadas para staging** (R4-9) — el routing de prod nunca las incluye.
- [ ] `max_contacts=5` por extensión (multi-dispositivo, §15.1).
- [ ] (Fase 2) PJSIP realtime para credenciales efímeras.

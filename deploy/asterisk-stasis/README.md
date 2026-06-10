# Asterisk Stasis App — cerebro de routing (VPS-2)

App Node que conecta a Asterisk vía **ARI** (WebSocket local en el VPS-2) y decide a qué asesor suena cada llamada, consultando a Rails. **No vive en el repo Rails**; corre junto a FreePBX/Asterisk.

## Por qué existe (no es Rails quien habla ARI)
ARI es Asterisk→app por WebSocket persistente. Rails/Puma no debe mantener ese socket cross-VPS. Esta app es el consumidor ARI local; habla con Rails por HTTP stateless (`/sip/routing`, `/sip/events`). Si Rails cae, aplica **fallback local** (manda a IVR/cola) y la telefonía no se cae.

## Flujo
```
StasisStart (llamada entra al contexto Stasis desde el dialplan FreePBX)
  → GET Rails /sip/routing?phone=<E164>&linkedid=<id>
      ├─ {extension, agent}  → Dial PJSIP/<ext> timeout 15s
      │     ├─ contesta  → POST /sip/events {answered, linkedid}  (Rails asigna conversación)
      │     └─ no contesta→ siguiente del RR (Rails) o buzón
      └─ {ivr:true}          → playback menú ciudades → getDigit
              → GET /sip/routing?team_digit=<n>&linkedid=<id>  (Rails: RR del Team)
              → Dial PJSIP/<ext> ... (igual)
Eventos de presencia (PJSIP register/unregister vía AMI o ARI deviceState)
  → POST /sip/events {sip_register|sip_unregister, extension}   (Rails actualiza sip_online)
Transferencia ciega (REFER del agente) → channels/{id}/redirect al destino
```

## Identidad de llamada
Usa **`Linkedid`** como `provider_call_id` en todos los POST a Rails (estable durante toda la llamada y el transfer). NO el `Channel id` (cambia por leg).

## Setup
```bash
cp .env.example .env   # completar ARI + Rails secret + URLs
npm install
npm start              # o pm2 / systemd
```

## Archivos
- `src/index.js` — conexión ARI + handler StasisStart + presencia.
- `src/railsClient.js` — cliente HTTP a Rails `/sip/*` (token).
- `src/routing.js` — Dial/IVR/transfer + fallback local.
- `.env.example` — variables.

## Pendiente de implementar (TODOs marcados en el código)
- Audios del IVR (subir a FreePBX, referenciar por nombre).
- Mapa de causes de hangup → ya lo traduce Rails (`ASTERISK_STATUS_MAP`); aquí solo se reenvía el `cause`.
- Reintentos/backoff del cliente Rails.

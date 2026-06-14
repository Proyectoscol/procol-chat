# Checklist de deploy a producción — ProCall VoIP

> Ejecutar en orden. Marcar cada ítem antes de dar por terminado el deploy.

---

## VPS-1 (EasyPanel) — Variables de entorno requeridas

Configurar en EasyPanel → App → Environment antes de (re)deployar:

```
SIP_WSS_HOST=freebpx.procol-proyectoscol.com
SIP_WSS_PORT=8089
SIP_INTERNAL_TOKEN=<openssl rand -hex 32>
SIP_ALLOWED_IPS=2.25.200.186
TURN_USERNAME=procol
TURN_CREDENTIAL=<openssl rand -hex 16>
```

> `SIP_WSS_URL` no es una variable de entorno del backend — se construye dinámicamente
> en `Sip::CredentialService#wss_url` a partir de `SIP_WSS_HOST` y `SIP_WSS_PORT`.

Generar valores seguros:
```bash
openssl rand -hex 32   # → SIP_INTERNAL_TOKEN
openssl rand -hex 16   # → TURN_CREDENTIAL
```

---

## VPS-2 — Servicios que deben estar activos

- [ ] **asterisk** — `asterisk -rx "core show version"`
- [ ] **coturn** — `systemctl status coturn`
- [ ] **stasis-routing** (Node/systemd) — `systemctl status stasis-routing`
- [ ] `/etc/asterisk/pjsip.endpoint_custom_post.conf` tiene bloque `[NNN] type=endpoint webrtc=yes` para cada extensión activa
- [ ] Firewall VPS-2: puerto 5060 UDP (SIP) y 10000-20000 UDP (RTP) abiertos hacia internet
- [ ] Firewall VPS-2: puerto 3478 UDP/TCP (TURN/coturn) abierto

---

## VPS-1 — Verificación post-deploy

- [ ] `GET /api/v1/accounts/:id/sip/credential` devuelve `wss_url` no-null
- [ ] ActionCable conecta en producción (ver cable.yml abajo — adapter: redis ✅)
- [ ] Contenedor Sidekiq activo en EasyPanel
- [ ] `SIP_ALLOWED_IPS` seteado con IP del VPS-2 (actualmente `2.25.200.186`)
- [ ] Token SIP rotado desde el valor de desarrollo
- [ ] Una llamada de prueba 9001↔9002 completa (ring + audio bidireccional)

---

## ActionCable — Estado actual de config/cable.yml

```yaml
# Estado real en el repo (config/cable.yml):
default: &default
  adapter: redis
  url: <%= ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379') %>
  password: <%= ENV.fetch('REDIS_PASSWORD', nil).presence %>
  channel_prefix: <%= "chatwoot_#{Rails.env}_action_cable" %>

production:
  <<: *default   # hereda adapter: redis ✅
```

**Verificar en producción:**
- `REDIS_URL` seteado en EasyPanel (el fallback apunta a localhost — falla en Docker)
- `REDIS_PASSWORD` seteado si el Redis tiene contraseña
- El `channel_prefix` en producción será `chatwoot_production_action_cable`
  (diferente al `procol_production` que pueda aparecer en docs anteriores — no hay
  conflicto funcional, solo naming)

---

## Secuencia de deploy

```
1. Merge custom → push a origin/custom
2. GitHub Actions construye imagen Docker (~20-30 min)
3. EasyPanel → App → Pull → Redeploy
4. Verificar logs de inicio: "Listening on tcp://0.0.0.0:3000"
5. Ejecutar checklist de verificación post-deploy
```

> Claude NO hace deploy. El redeploy en EasyPanel es manual.

---

## Rollback

Si el deploy falla:
1. EasyPanel → App → Deployments → seleccionar imagen anterior → Redeploy
2. Verificar que la imagen anterior es compatible con el schema de BD actual
   (si hubo migraciones, el rollback requiere `db:rollback` manual)

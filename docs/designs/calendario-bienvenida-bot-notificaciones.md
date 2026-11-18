# Design: Bot de Bienvenida (triage) + Notificaciones por servicio

Generated via conversación + /plan-eng-review (gstack) on 2026-11-18
Branch: calendario
Repo: Proyectoscol/procol-chat
Status: DRAFT — pendiente de aprobación antes de construir

## Problem Statement

Hoy, cada mensaje nuevo de WhatsApp lo triagea un humano a mano: pregunta "¿de qué
entidad?", "¿para qué especialidad?", cotiza precio si es particular, rechaza
entidades sin convenio (ej. FOMAG, rechazado desde el 1 de agosto — regla que el
personal tiene que recordar y repetir manualmente cada vez), y arma el mensaje de
confirmación de cita a mano copiando una plantilla mental que varía poco pero nunca
está escrita en un solo lugar. El "no asistió" no tiene ningún mensaje automático ni
botones de reprogramación.

## Demand Evidence

Se leyó una muestra real de 46 conversaciones de WhatsApp (exportadas, `chatsexport/`,
nunca versionadas en git) de pacientes reales abriendo chat por primera vez. Patrones
encontrados:

1. **5 formas distintas de abrir conversación**: saludo + petición directa, solo
   envían el documento/examen sin texto, preguntan precio/convenio antes que nada,
   terceros gestionando por el paciente (aseguradoras, intermediarios), o solo
   nombre+cédula (reconfirmando datos de lista de espera).
2. **Triage manual consistente**: "¿De qué entidad?" es la pregunta bisagra en casi
   el 100% de los chats sin contexto previo. Seguida de "¿Para qué especialidad?"
   cuando no es obvio, y preguntas específicas de servicio (embarazo para
   ginecología, resultado de urocultivo para seguimiento urología).
3. **Plantilla de confirmación ya estandarizada** (texto casi idéntico en 15+
   chats): nombre/fecha/hora/lugar → "Debe traer" (varía por servicio/aseguradora)
   → foto de instrucciones de preparación (varía por servicio) → "Por favor
   confirmar" + "Leer la preparación".
4. **Caso real de regla de negocio no automatizada**: paciente de FOMAG rechazado
   verbalmente porque "desde el 1 de agosto no estamos atendiendo pacientes de
   FOMAG" — el personal tiene que acordarse y explicarlo cada vez.

## Reuse Audit (lo que YA existe en Chatwoot, verificado leyendo código)

Esta es la pieza más importante del diseño: la mayoría de lo pedido ya tiene
mecanismo construido y probado en producción. Construir desde cero habría
duplicado lógica existente.

| Necesidad | Ya existe en | Verificado |
|---|---|---|
| Disparo por palabra clave en el primer mensaje | `AutomationRule` + condición `content` "contiene" | `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js:23-26` |
| Enviar un mensaje con botones reales en WhatsApp vía Twilio | `Twilio::TemplateProcessorService` soporta `template_type: quick_reply` | `app/services/twilio/template_processor_service.rb:26` — mismo mecanismo que ya usa `Calendario::AppointmentTriggerRunner` para confirmaciones de cita |
| Asignar la conversación a un humano al terminar el triage | `ActionService#assign_team` / `#assign_agent` | `app/services/action_service.rb:44-50,66-74` |
| Capturar la respuesta del botón tocado | `message.content` (viene por `Body` de Twilio) | `app/jobs/webhooks/twilio_events_job.rb:7` — todo pasa por `Body` |
| Confirmación de cita + recordatorio 24h/1h, filtrado por servicio/EPS | `Calendario::AppointmentEventTrigger` (ya construido en esta misma rama) | `app/models/calendario/appointment_event_trigger.rb` — `service_ids`, `payer_kinds`, `offset_minutes` ya soportan esto sin código nuevo |
| El guard de "ya pasó la hora, no lo mandes" para recordatorios | `Calendario::Appointment#schedule_before_start_triggers` | `app/models/calendario/appointment.rb:164-168` — `next if run_at <= Time.current` |

### Hallazgo crítico: condición de carrera con la auto-asignación

Una conversación nueva en Chatwoot nace con `status: open` por defecto
(`db/schema.rb`, columna `status` default `0`). El callback
`AutoAssignmentHandler#run_auto_assignment` (`app/models/concerns/
auto_assignment_handler.rb:12`) se dispara en `after_save`, y
`conversation_status_changed_to_open?` (`app/models/conversation.rb:341-345`)
devuelve `true` para **toda conversación recién creada** (`previous_changes.key?
(:id)` es cierto en cualquier alta). Es decir: **hoy, sin este proyecto, cualquier
mensaje nuevo de WhatsApp dispara la auto-asignación a un agente humano de
inmediato** — no existe ningún "modo bot" que retenga la conversación primero
(se buscó explícitamente un mecanismo tipo `status: pending` para inboxes con
bot activo — existía antes, el código está comentado como legacy en
`app/builders/conversation_builder.rb:26-27` y ya no se usa).

**Implicación para el diseño:** mientras el bot de Bienvenida esté activo en una
bandeja, hay que desactivar `inbox.enable_auto_assignment` (`app/models/
inbox.rb:15`) en esa bandeja —`should_run_auto_assignment?` respeta ese flag
(`auto_assignment_handler.rb:39`)— y el **propio bot** debe llamar a
`assign_team`/`assign_agent` como su paso final, re-habilitando
`enable_auto_assignment` después si se desea volver al comportamiento normal
fuera de horario de triage.

### Limitación conocida (no bloqueante, documentada)

`app/controllers/twilio/callback_controller.rb` no incluye `ButtonText`/
`ButtonPayload` en su whitelist de parámetros — los campos "limpios" que Twilio
manda cuando alguien toca un botón de WhatsApp. El texto del botón sí llega por
`Body` (confirmado en `twilio_events_job.rb`), así que el matching por texto
visible funciona, pero si más adelante se traduce o se retoca el texto de un
botón sin actualizar el flujo que lo espera, se rompe en silencio. Mejora futura
de bajo riesgo: agregar esos dos campos al whitelist.

## Scope

### Categorías de Notificaciones (confirmadas)

1. **Bienvenida** (bot de triage) — NUEVO, la pieza grande de este plan.
2. **Confirmación de cita — por servicio** — SIN código nuevo, solo configuración
   usando lo ya construido (`service_ids`/`payer_kinds` en `AppointmentEventTrigger`).
3. **No asistió (no-show)** — casi sin código nuevo: el envío reusa
   `AppointmentEventTrigger` (`on_status_change`, `target_status: no_show`); lo
   nuevo es capturar el botón "Reprogramar"/"Cancelar" y actuar.
4. **Recordatorio antes de la cita, 24h y 1h** — SIN código nuevo, ya soportado
   (ver guard de `run_at <= Time.current`: si se crea la cita para mañana, el de
   24h simplemente no corre y solo dispara el de 1h, exactamente lo pedido).

Explícitamente **fuera de alcance** (decisión del usuario): "Documentos/
autorización pendiente" y "Entidad no cubierta" como categorías separadas — no
se construyen por ahora.

## Data Model (lo único nuevo)

```ruby
# Configuracion de cada bot de triage -- varios pueden coexistir, elegidos por
# que texto escribio el paciente primero.
create_table :calendario_welcome_bot_flows do |t|
  t.references :account, null: false
  t.references :inbox, null: false        # a que bandeja de WhatsApp aplica
  t.string :name, null: false              # "Triage general", "Campaña IG nov"
  t.string :match_type, null: false        # "default" | "keyword"
  t.string :match_value                    # texto a buscar si match_type=keyword
  t.integer :priority, null: false, default: 0  # desempate si varios matchean
  t.jsonb :steps, null: false, default: []      # secuencia de preguntas/opciones
  t.boolean :active, null: false, default: true
  t.timestamps
end
# index unico: (account_id, inbox_id) con match_type=default -- solo puede haber
# UN default por bandeja (si no matchea ningun keyword, cae ahi).

# Estado de un triage en curso para una conversacion puntual.
create_table :calendario_bot_sessions do |t|
  t.references :account, null: false
  t.references :conversation, null: false
  t.references :welcome_bot_flow, null: false
  t.integer :current_step, null: false, default: 0
  t.jsonb :answers, null: false, default: {}     # respuestas dadas hasta ahora
  t.integer :reminder_count, null: false, default: 0
  t.datetime :last_prompted_at
  t.string :status, null: false, default: "active" # active | handed_off | reset
  t.timestamps
end
# index unico: conversation_id donde status=active -- una sola sesion activa
# por conversacion a la vez.
```

`steps` (jsonb) por flujo, ej. el triage general:
```json
[
  { "ask": "¿Para qué especialidad?", "options": ["Urología", "Ginecología"] },
  { "ask": "¿De qué entidad?", "options": ["Particular", "EPS/aseguradora"] },
  { "ask": "¿Cuál?", "options": ["Previser", "Colsanitas", "..."], "if": { "step": 1, "equals": "EPS/aseguradora" } }
]
```

## Flujo (Bienvenida)

```
Mensaje entrante nuevo
      │
      ▼
¿Existe BotSession activa para esta conversación?
      │                                   │
      No                                  Sí
      │                                   │
      ▼                                   ▼
¿Qué WelcomeBotFlow matchea?        WelcomeBotFlowRunner
(keyword por prioridad,              avanza el paso actual
luego "default")                     con la respuesta
      │                                   │
      ▼                                   ▼
Crea BotSession                     ¿Quedan pasos?
inbox.enable_auto_assignment=false        │         │
      │                                  Sí         No
      ▼                                   │          │
Manda la primera pregunta                 ▼          ▼
(quick_reply template)              Manda la      assign_team/assign_agent
                                     siguiente      inbox.enable_auto_assignment=true
                                     pregunta       BotSession.status = handed_off
```

Recordatorio (cadencia confirmada: 2 avisos cada 5 min, reset a los 20 min):
```
Pregunta enviada, sin respuesta
      │
   5 min sin responder ──► recordatorio #1 (reminder_count=1)
      │
   5 min más sin responder ──► recordatorio #2 (reminder_count=2)
      │
   20 min más sin responder ──► BotSession.status = "reset"
                                 (próximo mensaje de ese contacto reinicia
                                 el flujo desde cero, como si fuera nuevo)
```
Job idempotente (mismo patrón que `AppointmentTriggerFiring`): revisa
`last_prompted_at` + `reminder_count` antes de mandar, para que un atraso de
Sidekiq no dispare recordatorios en masa fuera de tiempo.

## Flujo (No-show con botones)

```
Cita pasa a status: no_show
      │
      ▼
AppointmentEventTrigger (on_status_change, ya existe) dispara
plantilla quick_reply: "Reprogramar" / "Cancelar definitivamente"
      │
      ▼
Paciente toca un botón ──► texto llega por Body
      │
      ├── "Reprogramar" ──► abre RescheduleAppointmentModal equivalente vía bot
      └── "Cancelar" ──► Appointment#cancel!
```

## Open Decisions (para resolver antes o durante la construcción)

1. **Botones quick_reply en Twilio requieren plantilla pre-aprobada** en la
   consola de Twilio/Meta (mismo proceso de aprobación que las plantillas de
   confirmación de cita ya usadas) — turnaround de horas a días, fuera del
   control del código. Hay que crear esas plantillas (triage, no-show) con
   tiempo antes de depender de ellas en producción.
2. **¿Qué pasa si el paciente responde con texto libre en vez de tocar el
   botón?** (ej. escribe "particular" en vez de tocar la opción). Recomendado:
   el runner matchea también por texto libre contra las `options` del paso
   actual (case-insensitive, sin tildes), no solo por tap exacto del botón.
3. **Alcance de "cualquier texto reinicia"**: tras el reset a los 20 min,
   ¿el PRIMER mensaje nuevo reinicia directo el flujo, o debe pasar otra vez por
   el matching de keyword/default? → Recomendado: pasa otra vez por el matching
   completo (consistente, un mensaje nuevo siempre se evalúa igual).

## Phasing (de menor a mayor riesgo)

- **Fase 0 — sin código nuevo:** crear en producción los `AppointmentEventTrigger`
  de Confirmación por servicio (uno por servicio, cada uno con su plantilla y su
  "debe traer") y los de Recordatorio 24h/1h. Esto ya se puede hacer HOY desde la
  UI de Notificaciones que ya construimos.
- **Fase 1 — pieza chica:** No-show con botones Reprogramar/Cancelar (reusa el
  trigger existente para el envío; lo nuevo es el handler del tap).
- **Fase 2 — la pieza grande:** `WelcomeBotFlow` + `BotSession` + runner + job de
  recordatorio/reset, con soporte multi-flujo por palabra clave desde el día uno
  (no se agrega después).

## NOT in scope

- "Documentos/autorización pendiente" y "Entidad no cubierta" como categorías de
  Notificaciones (decisión explícita del usuario).
- Migrar el canal de `Channel::TwilioSms` a `Channel::Whatsapp` (Cloud API/
  360dialog) — mencionado como posibilidad futura si se necesitan mensajes
  interactivos nativos (`input_select`) en vez de plantillas quick_reply, pero no
  es parte de este plan.

# Sesión 2026-11-24 (tarde/noche) — fixes post-import + valor de cita

Continuación de `SESION_2026-11-24_EXPORT_IMPORT_PRODUCCION.md` (la sesión
de la mañana). Esta cubre todo lo que pasó después de que el import ya
corrió en producción: bugs reales que aparecieron al usar los datos
importados de verdad, limpieza de la asignación masiva a Beatriz, y una
feature nueva (valor a cobrar por cita).

## 1. Commits de esta sesión (rama `calendario`, ya pusheados)

- `7c66a7e9a` — permitir crear contacto manual solo con teléfono (antes
  siempre exigía documento). Incluye fix de bug real: `identifier: ''`
  chocaba contra el índice único de Postgres (`'' != NULL`) — normalizado a
  `nil` en `Contact#prepare_identifier_attribute`, mismo patrón que ya
  existía para `email`. También: paridad de "crear contacto nuevo" en el
  modal de lista de espera, y clasificación automática del buscador
  (`app/javascript/dashboard/routes/dashboard/calendario/helpers/classifyContactQuery.js`):
  celular colombiano → teléfono, otro número → documento, texto → nombre.
- `be89c9359` — **bug real en producción, ya confirmado y corregido**:
  `Message#reopen_conversation` y `#set_conversation_activity` corrían para
  TODO mensaje sin distinguir histórico. Un mensaje importado podía reabrir
  una conversación ya resuelta, o retroceder `last_activity_at` a una fecha
  vieja. Ahora respetan `content_attributes.historical_import`. **No es
  retroactivo** — por eso se corrigió lo ya importado a mano por SQL (ver
  sección 2).
- `a75ccfdb9` — en el panel de contacto, si no hay teléfono pero sí username
  de WhatsApp (`social_whatsapp_user_name`), se muestra `@usuario` con
  ícono de mención en vez de "No Disponible". Verificado en navegador local.
- `493216aac` — "Cancelar cita" (bot de bienvenida) no mandaba ningún
  mensaje de confirmación al paciente, a diferencia de Reagendar/Handoff.
  Corregido + mensaje de "transferir a recepción" reescrito más profesional
  (compartido ahora entre Cancelar y Handoff).
- `284c849ca` — **feature nueva**: `amount_to_collect` (opcional) en
  `Calendario::Appointment`. El Liquid drop (`appointment.amount_to_collect`)
  prioriza este valor sobre `appointment.price` (precio de catálogo via
  `Calendario::ServicePrice`, por servicio×pagador) y lo formatea con
  separador de miles; vacío si ninguno aplica (para `{% if %}` en
  plantillas). UI en el formulario de citas. Pensado para cuando el doctor
  da un descuento puntual — el precio de catálogo sigue siendo la fuente de
  verdad por defecto.

## 2. Limpieza manual en producción (SQL directo, ya ejecutado y confirmado)

Al asignar en masa las conversaciones importadas a Beatriz (user id=3, el
texto "Asignado a X por Y" es un mensaje de actividad REAL, no histórico),
se detectaron dos problemas reales:

1. **Asignar desde la UI mueve `last_activity_at` a "ahora"** y manda
   notificación — para 285 conversaciones esto hubiera sido spam y hubiera
   desordenado las listas (Mías/Sin asignar/Todas, que ordenan por esa
   fecha). Se resolvió con `UPDATE conversations SET assignee_id = 3 WHERE
   ...` directo (sin pasar por la app) para las que NO tenían asignado
   todavía, y con un `UPDATE` de corrección de `last_activity_at` (usando
   `MAX(created_at)` de mensajes no-actividad) para las que YA se habían
   asignado desde la UI antes de darnos cuenta del problema. **285
   conversaciones** quedaron asignadas a Beatriz, todas con su fecha de
   actividad real conservada. Verificado con conteos antes/después.
2. **Bug de diagnóstico encontrado en el camino (no es un bug del
   producto)**: `content_attributes` quedó guardado en la BD como un string
   JSON doblemente codificado (ej. `"{\"historical_import\":true}"` en vez
   de un objeto real). El operador `->>'clave'` de Postgres no funciona
   sobre eso (siempre da NULL/vacío) — hay que usar
   `content_attributes::text ILIKE '%historical_import%'` como workaround.
   **Pendiente de arreglar en el código del import** (ver sección 4.1).

## 3. Hallazgo real sobre contactos solo-username (WhatsApp)

Contactos importados con solo `social_whatsapp_user_name` (sin teléfono)
**no pueden recibir mensajes salientes de Twilio nunca**, ni con plantilla
aprobada ni nada — Twilio/Meta exige un teléfono real o un identificador
interno (`CO.<numero>`, formato LID) que **solo WhatsApp asigna cuando la
persona escribe de verdad**, y ese LID no tiene ninguna relación derivable
del username. Confirmado comparando un contacto real que SÍ funciona (LID
real) contra uno importado que falla (`whatsapp:@usuario`, rechazado por
Twilio con error 21211). No hay API de Twilio/Meta para "buscar" el LID de
alguien a partir de su username -- por diseño de privacidad.

Única solución real: esperar a que la persona escriba, o conseguir su
número real por otro medio y actualizar el contacto a mano (`contacts.phone_number`
Y TAMBIÉN `contact_inboxes.source_id`, que es el campo que de verdad usa el
envío -- ver `app/services/twilio/send_on_twilio_service.rb:50,80`).

## 4. Pendientes para la próxima sesión

### 4.1. Bug: `content_attributes` doblemente codificado al exportar/importar
No se investigó la causa raíz (probablemente en
`Calendario::AccountDataExportService`, algo serializa el hash a JSON antes
de meterlo en el documento de export, y luego se vuelve a serializar al
guardar en el `json` column del destino). No rompe nada hoy gracias al
workaround con `ILIKE`, pero vale la pena arreglarlo para que futuros
imports no hereden el problema y para que `->>'clave'` funcione normal.

### 4.2. Bug: import no fabrica un `source_id` válido para contactos
solo-username
`Calendario::AccountDataImportService#source_id_for` genera
`"whatsapp:@username"` cuando el contacto no tiene teléfono -- Twilio
rechaza esto siempre (ver sección 3). Se propuso, pero no se implementó:
dejar de fabricar ese `source_id` falso (no crear `contact_inbox` para
estos casos, o marcarlos de alguna forma) para que el cajón de enviar
mensaje no aparezca como si fuera a funcionar.

### 4.3. Catálogo de servicios: falta correr en producción
`data_imports/calendario_agendas_dr_corrales_2026/split_consulta_ginecologia.rb`
-- separa el servicio compartido "Consulta" en "Consulta" (urología) +
"Consulta Ginecología", para que `Calendario::ServicePrice` pueda tener un
precio distinto por especialidad (hoy el sistema de precios es por
servicio×pagador, sin dimensión de profesional/especialidad). **Ya
probado en local, funciona** (movió 306 citas de la Dra. Cano
correctamente). Comando para producción:

```bash
docker compose -f docker-compose.production.yaml exec <servicio_rails> \
  bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/split_consulta_ginecologia.rb
```

Después de correrlo: configurar precios reales en `Ajustes → Servicios`
para "Consulta" y "Consulta Ginecología" (particular/EPS/plan
complementario/prepagada/póliza). Datos reales ya confirmados en chats
exportados: particular urología = $280.000 cuesta en efectivo, sin
datáfono; planes/prepagadas tipo "previser"/"unisser" = $150.000 de
copago (el monto varía por plan, no es universal). Falta el precio
particular de ginecología (no se encontró en los chats, hay que
preguntarle al usuario).

### 4.4. Plantillas reales de Twilio para "Al crear la cita" (Paso 3, sin empezar)
Diseño ya acordado con el usuario: 3 plantillas por tipo de pagador
(particular / copago-planes / EPS), usando `{{ appointment.price }}` o
`{{ appointment.amount_to_collect }}` como variable en vez de fijar el
precio en el texto. Falta:
1. Confirmar el texto final de las 3 plantillas con el usuario (ya hay
   precedente de redacción en
   `data_imports/calendario_agendas_dr_corrales_2026/create_appointment_templates.rb`
   -- `confirmacion_particular` y `confirmacion_eps` ya existen ahí pero
   `confirmacion_particular` tiene el precio HARDCODEADO ($280.000), hay
   que reescribirla con variable antes de someterla; `confirmacion_eps` no
   necesita cambios, ya no menciona dinero). Falta una plantilla nueva para
   el grupo copago (plan_complementario/prepagada/poliza).
2. Someter a aprobación de Meta (una vez aprobado un content template no se
   puede editar -- pensar bien el texto antes).
3. Configurar los 3 `Calendario::AppointmentEventTrigger` (uno por grupo de
   `payer_kinds`) con el `content_sid` real cuando esté aprobado, y
   desactivar `test_mode`.

### 4.5. Plantillas locales ya creadas en biblioteca (solo local, no producción)
`Calendario::MessageTemplate` (biblioteca de plantillas) ya tiene en LOCAL:
`bot_cita_existente_ask`, `bot_cita_existente_empty` (el usuario ya los
había editado con su propio tono/emojis), `bot_reagendar_ack`,
`bot_handoff_ack` (estos dos creados en esta sesión). **Faltan en
producción** -- correr el mismo script de creación (ver historial de esta
sesión si se necesita, o pedirlo de nuevo) contra el VPS, ajustando el
texto de ask/empty a lo que el usuario ya tiene en local si se quiere
igualar.

## 5. Pendientes heredados de la sesión de la mañana (sin tocar en esta)
Ver `SESION_2026-11-24_EXPORT_IMPORT_PRODUCCION.md` sección 5: punto 5.3
(¿más columnas huérfanas en producción?) sigue sin decidir; punto 5.4 (si
se commitea `create_appointment_templates.rb`) sigue pendiente -- ahora
hay un segundo script sin commitear (`split_consulta_ginecologia.rb`),
misma pregunta aplica a los dos.

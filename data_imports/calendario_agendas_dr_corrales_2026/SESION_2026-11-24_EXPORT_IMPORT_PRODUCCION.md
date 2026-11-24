# Sesión 2026-11-24 — Export/Import a producción + bot manual + bugs encontrados

Documento de cierre de una sesión muy larga, antes de limpiar el contexto del
chat. Cubre: qué se construyó, qué bugs reales se encontraron y corrigieron, y
qué queda pendiente para la próxima sesión.

## 1. Feature principal: Export/Import de datos entre instancias

Nueva página en `Ajustes → Exportar / Importar datos`, pensada para migrar
todo el histórico local (profesionales, servicios, EPS, especialidades,
contactos, conversaciones+mensajes+adjuntos, citas, lista de espera) a
producción antes de conectar el número real de WhatsApp.

**Arquitectura**: `Calendario::AccountDataExport`/`AccountDataImport`
(modelos) + `AccountDataExportService`/`AccountDataImportService` (lógica) +
`AccountDataTransferSpec` (fuente única de verdad: qué modelos, en qué orden,
qué columnas se excluyen/remapean). Jobs en background
(`Calendario::AccountDataExportJob`/`ImportJob`), encolados automáticamente
10s después de crear el registro (mismo patrón que `Import::WhatsappChatBatch`).

**Deliberadamente NO incluye** automatizaciones (disparadores, bot de
bienvenida, plantillas, paciente que regresa) — esas se configuran de nuevo en
cada instancia, revisadas con calma antes de activarlas con pacientes reales.

**Doctrina de seguridad**: todo mensaje importado queda forzado a
`private: true` + `content_attributes.historical_import: true`, sin importar
lo que diga el export — nunca puede disparar un envío real. Toda cita
importada usa `historical_import: true` (ya soportado nativamente por el
modelo), saltando validaciones de fecha pasada y disparadores.

**Es siempre aditivo**: nunca borra ni reemplaza nada existente. Si un
contacto ya existe en el destino (mismo teléfono), lo reutiliza y le cuelga
el historial nuevo en vez de duplicarlo — mismo criterio para
`contact_inbox` (mismo `source_id` que generaría el canal real) y
`conversation` (misma bandeja+contacto). Esto significa que si un contacto YA
escribió de verdad en producción antes de importar su histórico, el import
fusiona todo en la MISMA conversación real sin duplicar ni fallar.

### Commits (rama `calendario`)
- `ea009da40` — feature completa (modelos, servicios, controladores, UI).
- `db0f3d8a1` — fix: el export excluía `sender_id` de los mensajes, perdiendo
  el remitente real al importar (todo se veía como "saliente"/del negocio).
- `e2ad02daa` — fix: el import ahora ignora columnas que existan en origen
  pero no en destino (`filter_columns`), para tolerar desfase de esquema
  entre instancias.
- `9dfb05d98` — feature nueva: disparo manual del bot de bienvenida desde la
  conversación (ver sección 2).
- `b53dcac88` — **fix crítico**: savepoint por fila al importar (ver sección 3).

## 2. Feature nueva: disparo manual del bot de bienvenida

Pedido del usuario: para conversaciones que llegaron como histórico
(solo notas privadas, nunca dispararon el bot de verdad), poder desde la
conversación elegir un flujo activo por nombre y arrancarlo manualmente, con
las MISMAS consecuencias reales que un arranque automático (mensaje real por
WhatsApp, recordatorios, entrega a un humano).

- Nuevo panel "Bot de bienvenida" en el sidebar de la conversación (debajo de
  "Agenda del paciente").
- Backend: `Calendario::WelcomeBotFlowRunner` refactorizado para aceptar un
  `flow:` explícito (antes solo aceptaba `message:` e inferÍa el flujo por
  palabra clave) — mismo motor, mismas consecuencias.
- Nuevo endpoint `POST /conversations/:id/welcome_bot_trigger`
  (`Api::V1::Accounts::Conversations::WelcomeBotTriggersController`).
- Bloquea el envío si: ya hay sesión de bot activa, el contacto no tiene
  teléfono, o el flujo no es de esa bandeja.
- Advierte (no bloquea) si el primer paso del flujo no usa una plantilla
  aprobada de WhatsApp (puede fallar si el paciente no escribió en 24h).
- Verificado end-to-end por HTTP real en local (caso negativo: contacto sin
  teléfono → error limpio, nunca llega a Twilio).

## 3. Bug crítico encontrado y corregido: savepoint por fila

**Síntoma en producción**: al importar, `contacts: errors=3080` (el total
completo), y en cascada `appointment_audit_logs`/`waitlist_entries` también
al 100% de error, aunque los datos eran válidos.

**Causa raíz**: todo el import corría dentro de UNA sola transacción grande
(`ActiveRecord::Base.transaction` envolviendo los 17 modelos). En Postgres, en
cuanto UN solo INSERT falla de verdad (en este caso: un contacto con
`phone_number` duplicado — probablemente contra un contacto real que YA
existía en producción por tráfico real reciente), toda la transacción queda
"abortada" a nivel de conexión, y CUALQUIER sentencia SQL siguiente falla con
`PG::InFailedSqlTransaction: current transaction is aborted` — en cascada,
sin importar si esos datos eran válidos o no.

**Fix**: cada fila ahora corre en su propio savepoint
(`ActiveRecord::Base.transaction(requires_new: true)` dentro de
`import_rows`), así un error real queda aislado a esa fila nada más.

**Verificación exhaustiva**:
1. Prueba unitaria controlada: 3 filas, la del medio con un duplicado real
   forzado a propósito → `{created: 2, errors: 1}` (las otras dos NO se
   vieron afectadas).
2. Ciclo completo real cuenta 1 → cuenta 2 en local, vía el mecanismo REAL de
   Sidekiq (no llamada manual) → **0 errores en los 17 modelos**, conteos
   idénticos al manifest original.

**Gotcha de testing descubierto en el camino** (anotado para no repetirlo):
`Calendario::AccountDataImport`/`AccountDataExport` tienen
`after_create_commit` que encola un job real. Si además se llama
`.perform` manualmente en un script de prueba mientras Sidekiq está vivo, el
job encolado TAMBIÉN corre en paralelo — se corren dos imports a la vez sobre
el mismo registro, duplicando datos e inflando los conteos de forma muy
confusa. Para probar de verdad: o se deja que el job real lo procese solo
(no llamar `.perform` manualmente), o se usa una cuenta/Sidekiq
desconectado.

## 4. Otro bug real encontrado (no relacionado al import): `internal` columna huérfana

Producción no tenía la columna `contacts.internal` que SÍ existe en el
schema local — no por una migración pendiente (`db:migrate:status` mostraba
todo "up"), sino porque en algún momento se "aplastaron" migraciones viejas
dentro de `schema.rb` sin que ese archivo específico de migración llegara a
correr en la base de producción real. Fix defensivo ya aplicado
(`e2ad02daa`): el import ahora recorta cada fila a `klass.column_names` del
modelo destino antes de crear el registro, así nunca vuelve a fallar por este
tipo de desfase. **No se tocó el schema de producción** — no hacía falta para
que el import funcione, aunque puede valer la pena investigar aparte si hay
MÁS columnas con el mismo problema en otras tablas.

## 5. Pendientes para la próxima sesión (NO arreglados todavía)

### 5.1. Crítico: no se pueden crear contactos manualmente
`Api::V1::Accounts::ContactsController#create` (línea ~90) exige
`identifier` + `document_type` obligatorios en la creación manual vía el
formulario "Nuevo contacto" (decisión de diseño documentada: "Premisa 7" /
memoria `calendario-contact-doc-scope-boundary` — el documento es
obligatorio SOLO en esta superficie, nunca a nivel de modelo ni en builders
automáticos de canal).

**El bug real**: el formulario del frontend
(`app/javascript/dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue`,
renderizado por `CreateNewContactDialog.vue`) **no tiene ningún campo** para
`identifier`/`document_type`. Confirmado por grep: cero coincidencias. Así
que CUALQUIER intento de crear un contacto manualmente desde la UI falla con
`{message: "Identifier document is required", attributes: ["identifier"]}`,
sin que el usuario pueda siquiera ver el campo que falta.

**Para la próxima sesión**: agregar los campos `document_type` (select,
enum ya existe en `Contact`: `cc/ti/ce/pa/rc/pep/ppt`) + `identifier` al
formulario `ContactsForm.vue`, condicionados a `is-new-contact` (no deberían
aparecer o ser obligatorios al editar un contacto existente que ya fue
creado por un canal automático).

### 5.2. Falta paridad: crear contacto nuevo desde el modal de lista de espera
El botón "Agregar" del modal de lista de espera (lleva a "Nuevo contacto en
lista de espera") NO tiene la opción `No encuentro a "xxx xxx" → crear
contacto nuevo` que SÍ tiene el flujo de "Agregar cita" desde las tarjetas
globales de agenda. Pedido explícito del usuario: que ambos flujos tengan la
misma capacidad de crear un contacto nuevo sobre la marcha si no se
encuentra en la búsqueda.

**Para la próxima sesión**: ubicar el componente del modal de "Nuevo contacto
en lista de espera" (buscar por el texto del botón "Agregar" cerca de
`waitlist`/`lista de espera` en `app/javascript/dashboard/routes/dashboard/calendario/`),
comparar contra el componente equivalente del flujo de "Agregar cita" que SÍ
tiene esta opción, y replicar el mismo patrón (probablemente un
`AsyncSelect`/combobox con una opción especial al final de los resultados
vacíos que abre el drawer/modal de creación de contacto).

### 5.3. Sin decidir: ¿hay más columnas huérfanas en producción además de `contacts.internal`?
El fix de `filter_columns` ya protege contra esto para el import, pero no se
investigó si existen otras tablas con el mismo desfase esquema
local-vs-producción. No es bloqueante (el import ya es tolerante a esto),
pero vale la pena un chequeo si surgen más sorpresas.

### 5.4. El script `create_appointment_templates.rb` sigue sin decidir si se commitea
`data_imports/calendario_agendas_dr_corrales_2026/create_appointment_templates.rb`
(no trackeado en git) — creó y sometió a aprobación de Meta las 9 plantillas
reales de confirmación/recordatorio/cancelación/etc. Las 9 quedaron en
`pending` de aprobación la última vez que se revisó. Falta:
1. Confirmar con `Ajustes → Entradas → bandeja WhatsApp → Sync Templates` si
   ya se aprobaron.
2. Si se aprobaron: entrar a cada uno de los 12 `AppointmentEventTrigger`
   (`Ajustes → Mensajería → Notificaciones`), elegir la plantilla real
   correspondiente, confirmar el mapeo de variables (ya documentado en la
   salida del script), y desactivar `test_mode`.
3. Decidir si el script en sí se deja commiteado como referencia o se
   descarta (nunca se resolvió esta pregunta).

## 6. Estado de los datos de prueba (cuenta 2 "Acme Org", local)

Tiene datos reales de la cuenta 1 importados ahí (para pruebas de
roundtrip) — el usuario pidió explícitamente dejarlos ahí ("Déjalos ahí") en
vez de limpiarlos. Están ahí en este momento, resultado del último ciclo
limpio y exitoso (import id=12, 0 errores). Si se necesita limpiar de nuevo
antes de la próxima ronda de pruebas, el bloque de limpieza ya probado es:

```ruby
ActiveRecord::Base.transaction do
  Calendario::AccountDataImport.where(account_id: 2).delete_all
  Calendario::WaitlistEntry.where(account_id: 2).delete_all
  Calendario::AppointmentAuditLog.where(account_id: 2).delete_all
  Calendario::Appointment.where(account_id: 2).delete_all
  Attachment.joins(:message).where(messages: { account_id: 2 }).destroy_all
  Message.where(account_id: 2).delete_all
  Conversation.where(account_id: 2).delete_all
  ContactInbox.joins(:contact).where(contacts: { account_id: 2 }).delete_all
  Contact.where(account_id: 2).delete_all
  Calendario::OpenDay.where(account_id: 2).delete_all
  Calendario::ServiceProfessional.joins(:service).where(calendario_services: { account_id: 2 }).delete_all
  Calendario::ServicePrice.joins(:service).where(calendario_services: { account_id: 2 }).delete_all
  Calendario::ProfessionalAvailability.joins(:professional).where(calendario_professionals: { account_id: 2 }).delete_all
  Calendario::Professional.where(account_id: 2).delete_all
  Calendario::Service.where(account_id: 2).delete_all
  Calendario::Payer.where(account_id: 2).delete_all
  Calendario::Specialty.where(account_id: 2).delete_all
end
```

## 7. Gotcha operativo: este dev box tiene stray Sidekiq workers con backlog viejo

Ya documentado en memoria del proyecto, pero reconfirmado esta sesión: la
cola `low` (donde corren los jobs de export/import) tiene prioridad ESTRICTA
en `config/sidekiq.yml` — si la cola `medium`/`default` tiene miles de jobs
viejos acumulados (como pasa en este dev box desde hace semanas), un job en
`low` puede quedarse "En cola" indefinidamente. Para pruebas puntuales, correr
el servicio directo (`Calendario::AccountDataImportJob.new.perform(id)`) sin
pasar por la cola, PERO solo cuando se está seguro de que el
`after_create_commit` del modelo no va a disparar también el job real en
paralelo (ver gotcha de la sección 3).

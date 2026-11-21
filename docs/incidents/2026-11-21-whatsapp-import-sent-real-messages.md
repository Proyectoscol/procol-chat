# Incidente: la importación masiva de chats de WhatsApp envió 674 mensajes reales

Fecha: 2026-11-21. Branch: calendario. Repo: Proyectoscol/procol-chat.

## Qué pasó

Se corrió una importación masiva de 166 exports históricos de WhatsApp (`Import::WhatsappChatImportService`, feature ya construida y "verificada" en 2026-10-31, ver `[[project_whatsapp_chat_import]]` en memoria) para cargar conversaciones viejas a Chatwoot, vinculándolas a contactos ya existentes (importados del Excel) cuando el número coincidía.

El importador crea los mensajes históricos directamente en la base de datos (`Message.create!`), nunca llama a Twilio para enviarlos — eso está bien diseñado y se verificó de nuevo en este incidente (0 llamadas a `api.twilio.com` atribuibles al importador en los logs).

El problema real: **cada mensaje entrante creado dispara el evento `message_created` de Chatwoot**, y `Calendario::WelcomeBotListener` escucha ese evento sin distinguir si el mensaje es historia importada o una conversación nueva de verdad. Las 166 conversaciones importadas terminaban en un mensaje entrante, sin agente asignado — exactamente la condición que el bot de bienvenida usa para decidir "esto es un paciente nuevo escribiendo por primera vez". El bot arrancó el flujo de triage real para cada una, y como esa bandeja (`Prueba`, Twilio WhatsApp) sí tiene credenciales reales conectadas, **el saludo y los botones del bot sí se enviaron por Twilio de verdad**.

## Impacto medido

- **674 mensajes reales enviados** por Twilio (confirmado por `source_id` con el formato real de Twilio, `SM.../MM...`, no la huella sha256 que usa el importador).
- **159 de las 166 conversaciones importadas** recibieron al menos un mensaje real.
- **59 sesiones de bot quedaron activas** después del primer disparo — con riesgo real de seguir enviando recordatorios automáticos (`Calendario::BotSessionReminderJob`, corre periódicamente) si no se detenían.
- **13 pacientes reales alcanzaron a responder** antes de que se detuviera (ver tabla en la conversación de esta sesión con sus conversation_id, nombre y teléfono — no se repite aquí para no duplicar dato de pacientes real en un archivo versionado).

## Qué se hizo para contener el incidente (en orden)

1. Se confirmó con los logs que ningún mensaje saliente nuevo (sin marcar como importado) seguía pendiente de enviarse en el momento del hallazgo.
2. Se puso `status: 'handed_off'` a las 59 `Calendario::BotSession` que seguían `active` sobre las conversaciones afectadas -- `Calendario::BotSessionReminderJob` vuelve a consultar `BotSession.active` en cada corrida (no trabaja sobre una lista vieja en memoria), así que esto detuvo cualquier recordatorio futuro de inmediato.
3. Se identificaron los 13 pacientes que ya habían respondido, para que el personal les responda manualmente y evite más confusión.
4. **No se reintentó la importación de las conversaciones restantes** hasta corregir la causa de raíz (ver abajo).

## Causa raíz y corrección permanente

`Import::WhatsappChatImportService#message_params` no marcaba los mensajes entrantes de ninguna forma distinguible (los salientes sí llevaban `content_attributes: { external_echo: true }`, pero eso solo protege contra REENVIAR ese mismo mensaje -- `Base::SendOnChannelService#invalid_message?` se niega a mandar algo con `source_id` presente -- nunca protegía contra que OTRO mensaje nuevo, generado en respuesta por un listener, se enviara).

**Corrección aplicada** (commit en esta misma rama):
- `Import::WhatsappChatImportService#message_params` ahora pone `historical_import: true` en `content_attributes` de **todo** mensaje que crea, entrante o saliente.
- `Calendario::WelcomeBotListener#message_created` y `Calendario::NoShowReplyListener#message_created` ahora revisan esa marca de primero y no hacen nada si está presente -- un mensaje histórico jamás puede disparar el bot de bienvenida ni cancelar/reagendar una cita real por una coincidencia de texto.

## Por qué no se detectó antes de correr la importación completa

La feature se había "verificado end-to-end" en 2026-10-31 con un solo chat de prueba, en una cuenta/bandeja donde el bot de bienvenida de Calendario **todavía no existía** (se construyó varias semanas después, el 18 de noviembre). Nadie volvió a probar la importación después de que el bot de bienvenida se agregó al mismo inbox -- la combinación de las dos features nunca se probó junta hasta esta corrida real con 166 conversaciones.

## Lección para cualquier import/seed futuro que cree Messages o Conversations

Cualquier script que inserte mensajes históricos directamente en la base de datos (no solo este) **debe** marcar `content_attributes: { historical_import: true }` en cada mensaje que cree, y cualquier listener nuevo que reaccione a `message_created` **debe** empezar revisando esa marca antes de hacer nada que le llegue a un paciente real (enviar mensaje, cambiar estado de una cita, asignar un agente). Esto no es específico de WhatsApp -- aplica a cualquier canal.

## Pendiente (no resuelto en este incidente, requiere decisión del usuario)

- Las ~82 conversaciones restantes del export (76 que quedaron en `needs_review` por número inválido o remitente no encontrado, más las que no se intentaron) siguen sin importar. Una vez el usuario confirme que el riesgo está controlado, se puede reintentar con el guard ya puesto.
- No se revirtieron los mensajes reales ya enviados (no hay forma de "deshacer" un WhatsApp real) ni las respuestas de los 13 pacientes -- eso requiere que el personal les responda manualmente, fuera del alcance de este fix de código.

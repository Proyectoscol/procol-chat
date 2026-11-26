# Exenta una conversacion del bot de bienvenida de forma permanente --
# separado de Calendario::AppointmentTriggerRunner para no inflar esa clase
# con una responsabilidad aparte (orquestar el estado de exencion de una
# conversacion, no solo resolver variables y llamar a Twilio).
#
# Usado cuando se entrega una notificacion de cita SIN botones interactivos
# (confirmacion/cancelacion/reprogramacion) -- BUG REAL encontrado
# 2026-11-26: esa conversacion nace sin agente asignado y SIN ninguna
# Calendario::BotSession historica, asi que
# Calendario::WelcomeBotListener#already_handled_today? (pensado para "ya se
# entrego tras un triage completo") no la cubria, y cualquier respuesta del
# paciente (un clic en "He leido las indicaciones", o cualquier texto)
# arrancaba el Triaje general desde cero.
#
# Revisado con Codex (2026-11-26) antes de desplegar -- 3 correcciones
# reales sobre la primera version:
# 1. Si la conversacion REUTILIZADA ya tiene una BotSession ACTIVA en este
#    momento (el paciente esta a mitad de un triage o flujo interactivo
#    totalmente distinto, sin relacion con esta notificacion), NO se toca:
#    ni se asigna agente ni se marca el flag. Marcarlo igual dejaria la
#    conversacion permanentemente exenta del bot en cuanto esa sesion ajena
#    terminara, por una notificacion que no tenia nada que ver.
# 2. La asignacion corre dentro de `with_lock` (SELECT FOR UPDATE +
#    transaccion), releyendo assignee_id DESPUES del lock, no antes -- sin
#    esto, dos llamadas concurrentes (ej. esta y el auto-asignador generico
#    de Chatwoot) podian leer "sin asignar" ambas y la segunda pisaba
#    silenciosamente la asignacion de la primera.
# 3. El flag se escribe con jsonb_set a nivel de SQL (UPDATE atomico), no
#    con `additional_attributes.merge(...)` en Ruby -- un merge en memoria
#    seguido de `update!` es un read-modify-write: si otro proceso escribe
#    additional_attributes entre la lectura y la escritura (ej.
#    Crm::BaseProcessorService, u otro listener), uno de los dos cambios se
#    pierde en silencio. jsonb_set corre atomico dentro del propio UPDATE,
#    sin ventana de carrera.
class Calendario::WelcomeBotExemption
  pattr_initialize [:conversation!]

  def apply!
    return if Calendario::BotSession.active.exists?(conversation: conversation)

    assign_agent_if_missing!
    mark_skip_welcome_bot!
  end

  private

  def assign_agent_if_missing!
    conversation.with_lock do
      next if conversation.assignee_id.present?

      Calendario::WelcomeBotAssignmentService.new(conversation: conversation).perform
    end
  end

  def mark_skip_welcome_bot!
    return if conversation.additional_attributes['skip_welcome_bot'].present?

    Conversation.where(id: conversation.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      "additional_attributes = jsonb_set(coalesce(additional_attributes, '{}'::jsonb), '{skip_welcome_bot}', 'true'::jsonb, true)"
    )
    conversation.additional_attributes['skip_welcome_bot'] = true
  end
end

# Arranca (o aplaza) la Calendario::BotSession interactiva de un recordatorio
# con botones (confirmar/cancelar/reagendar) -- separado de
# Calendario::AppointmentTriggerRunner para no inflar esa clase con una
# responsabilidad aparte (orquestar sesiones de bot, no solo resolver
# variables y llamar a Twilio).
#
# Un trigger queda "interactivo" al configurarle bot_flow_id en
# template_params (picker en AppointmentEventTriggerFormModal, fase de
# botones) -- sin eso, #defer? siempre es false y #start! no hace nada.
#
# Solo puede haber UNA Calendario::BotSession activa por conversacion
# (constraint de base de datos). Pedido explicito del usuario 2026-11-26: si
# el paciente ya esta a mitad de otra conversacion con el bot cuando toca
# enviar el recordatorio, se APLAZA hasta que esa sesion termine -- nunca se
# manda sin botones inteligentes. Tope de reintentos para no aplazar para
# siempre si algo deja una sesion viva indefinidamente; pasado el tope se
# manda igual, sin sesion interactiva, antes que perder el recordatorio.
class Calendario::AppointmentReminderBotSession
  pattr_initialize [:trigger!, :appointment!, { defer_attempt: 0 }]

  MAX_DEFER_ATTEMPTS = 6
  DEFER_DELAY = 10.minutes

  def interactive?
    trigger.template_params['bot_flow_id'].present?
  end

  def defer?(conversation)
    return false unless interactive?
    return false if conversation.blank?
    return false unless Calendario::BotSession.active.exists?(conversation: conversation)
    return report_defer_limit_reached if defer_attempt >= MAX_DEFER_ATTEMPTS

    Calendario::AppointmentTriggerReminderJob.set(wait: DEFER_DELAY)
                                             .perform_later(trigger.id, appointment.id, defer_attempt + 1)
    true
  end

  # source_message_sid: el SID de Twilio del mensaje con botones que ya se
  # mando (el recordatorio) -- ver auditoria con Codex 2026-11-27, hallazgo
  # #6: sin esto, un boton viejo de OTRO recordatorio en la misma
  # conversacion podia accionar esta sesion.
  def start!(conversation, source_message_sid: nil)
    return unless interactive?
    return if Calendario::BotSession.active.exists?(conversation: conversation)

    flow = Calendario::WelcomeBotFlow.find_by(id: trigger.template_params['bot_flow_id'], account: appointment.account)
    return if flow.blank?

    Calendario::BotSession.create!(
      account: appointment.account, conversation: conversation, welcome_bot_flow: flow,
      current_step: 0, answers: { '_appointment_id' => appointment.id }, status: 'active',
      source_message_sid: source_message_sid
    )
  rescue ActiveRecord::RecordNotUnique
    nil # carrera real con otra sesion -- la plantilla igual sale, sin sesion interactiva
  end

  private

  def report_defer_limit_reached
    message = "AppointmentEventTrigger##{trigger.id}: tope de aplazamientos alcanzado " \
              "(cita ##{appointment.id}), se envia sin sesion interactiva."
    ChatwootExceptionTracker.new(StandardError.new(message), account: appointment.account).capture_exception
    false
  end
end

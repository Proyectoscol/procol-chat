# Idea del usuario (ver data_imports/calendario_agendas_dr_corrales_2026/
# ideas.txt, punto 5): Calendario::WelcomeBotListener SOLO corre para
# conversaciones sin agente asignado -- un paciente que ya tiene agente
# (triage completo hace dias, o escribio de nuevo en otra fecha) nunca
# recibe ningun mensaje automatico, aunque tenga una cita proxima y muy
# probablemente este escribiendo por eso mismo. Este listener cubre
# exactamente ese hueco, sin tocar en nada el flujo de Calendario::BotSession
# (que sigue siendo solo para conversaciones nuevas/sin asignar).
#
# Disparo del mensaje (una sola vez por cita, nunca reinicia el triage ni
# toca la asignacion existente):
#   - la conversacion YA tiene agente asignado
#   - el contacto tiene una cita futura en pending/confirmed
#   - esa cita todavia no recibio este mensaje (columna
#     returning_patient_prompt_sent_at)
#   - el mensaje entrante llega en un dia de calendario distinto al del
#     mensaje entrante anterior en la misma conversacion (evita mandarlo
#     de nuevo si la persona sigue escribiendo el mismo dia)
#
# Respuesta del paciente (reprogramar/cancelar, mismas palabras clave que
# Calendario::NoShowReplyListener via AppointmentReplyKeywordClassifier):
# una vez se mando el mensaje para una cita, cualquier mensaje posterior
# del mismo contacto se intenta clasificar contra ESA cita -- "hablar con
# recepcion" o cualquier otro texto simplemente no hace nada especial, el
# mensaje sigue su curso normal hacia el agente ya asignado.
class Calendario::ReturningAppointmentPromptListener < BaseListener
  include Calendario::WelcomeBotMessaging
  include Calendario::AppointmentReplyKeywordClassifier

  def message_created(event)
    message, account = extract_message_and_account(event)
    return if skip?(message)

    @conversation = message.conversation
    return if config.blank?

    if (prompted = prompted_appointment_for(conversation))
      handle_reply(prompted, message)
      return
    end

    maybe_send_prompt(message)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  private

  attr_reader :conversation

  delegate :account, :inbox, to: :conversation

  def config
    @config ||= Calendario::ReturningAppointmentPromptConfig.find_by(inbox_id: inbox.id, active: true)
  end

  def maybe_send_prompt(message)
    return if conversation.assignee_id.blank?
    return if Calendario::BotSession.active.exists?(conversation: conversation)

    candidate = next_unprompted_appointment_for(conversation)
    return if candidate.blank?
    return unless new_calendar_day?(conversation, message)

    send_prompt(candidate)
  end

  # Mismo guard de siempre -- nunca reaccionar a un chat historico importado.
  def skip?(message)
    return true unless message.incoming? && !message.private?
    return true if message.content_attributes['historical_import']

    message.content.blank?
  end

  def next_unprompted_appointment_for(conversation)
    upcoming_appointments_for(conversation).where(returning_patient_prompt_sent_at: nil).first
  end

  def prompted_appointment_for(conversation)
    upcoming_appointments_for(conversation).where.not(returning_patient_prompt_sent_at: nil).first
  end

  def upcoming_appointments_for(conversation)
    contact_id = conversation.contact_id
    return Calendario::Appointment.none if contact_id.blank?

    Calendario::Appointment
      .where(account_id: conversation.account_id, contact_id: contact_id, status: %i[pending confirmed])
      .upcoming
      .order(starts_at: :asc)
  end

  # Compara el dia de calendario (zona del reporting del negocio, no UTC)
  # del mensaje entrante anterior contra el de este -- si no hay un
  # entrante anterior, no hay "otro dia" con que comparar, asi que no
  # aplica (una conversacion que apenas arranca con agente ya asignado no
  # es el caso que este listener busca).
  def new_calendar_day?(conversation, message)
    previous = conversation.messages.incoming.where.not(id: message.id).order(created_at: :desc).first
    return false if previous.blank?

    local_date(previous.created_at) != local_date(message.created_at)
  end

  def local_date(time)
    time.in_time_zone(zone).to_date
  end

  def zone
    account.reporting_timezone.presence || 'UTC'
  end

  def send_prompt(appointment)
    step = {
      'ask' => render_liquid(config.resolved_ask_template, appointment),
      'options' => config.resolved_options,
      'content_sid' => config.content_sid
    }
    config.test_mode? ? create_test_mode_preview(step) : dispatch_prompt(step)
    appointment.update!(returning_patient_prompt_sent_at: Time.current)
  end

  def dispatch_prompt(step)
    step['content_sid'].present? ? send_whatsapp_buttons(step) : send_text_question(step)
  end

  # test_mode (default true, ver Calendario::ReturningAppointmentPromptConfig):
  # mismo patron de seguridad que Calendario::AppointmentTriggerRunner#create_private_note
  # -- nunca sale un mensaje real al paciente mientras este activo, para que
  # el usuario pueda probar en produccion antes de mandarlo de verdad.
  def create_test_mode_preview(step)
    create_private_note("[PRUEBA -- este mensaje de seguimiento esta en modo de prueba, nunca se envio un mensaje real]\n\n#{step_body(step)}")
  end

  def render_liquid(template, appointment)
    Liquid::Template.parse(template).render!('appointment' => Calendario::AppointmentDrop.new(appointment))
  rescue Liquid::Error
    template
  end

  def handle_reply(appointment, message)
    case classify_appointment_reply(message.content)
    when :reschedule then handle_reschedule(appointment)
    when :cancel then handle_cancel(appointment)
    end
  end

  def handle_reschedule(appointment)
    appointment.update!(status: :pending)
    create_private_note(
      "El paciente escribió de nuevo preguntando por su cita de #{appointment.service.name} " \
      "del #{formatted_date(appointment)} y pidió reagendarla (agente ya asignado, sin reiniciar el bot)."
    )
  end

  def handle_cancel(appointment)
    appointment.cancel!
    create_private_note(
      "El paciente escribió de nuevo preguntando por su cita de #{appointment.service.name} " \
      "del #{formatted_date(appointment)} y la canceló (agente ya asignado, sin reiniciar el bot)."
    )
  end

  def formatted_date(appointment)
    Calendario::SpanishDateFormatter.long_date_time(appointment.starts_at.in_time_zone(zone))
  end
end

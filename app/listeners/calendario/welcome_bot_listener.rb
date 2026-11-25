class Calendario::WelcomeBotListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.incoming? && !message.private?
    # Nunca reaccionar a un mensaje historico importado (ej. bulk-import de
    # exports de WhatsApp) -- ver incidente documentado en
    # data_imports/.../INCIDENTE_welcome_bot_import.md: sin este guard, 166
    # conversaciones importadas se confundieron con conversaciones nuevas de
    # verdad y el bot mando 674 mensajes reales por Twilio a pacientes reales.
    return if message.content_attributes['historical_import']

    conversation = message.conversation
    flow = Calendario::WelcomeBotFlow.match_for(conversation.inbox, message.content, conversation: conversation)
    return if flow.blank?
    return if already_handled_today?(conversation, message)

    Calendario::WelcomeBotFlowRunner.new(conversation: conversation, message: message, flow: flow).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  private

  # Una vez entregada a un agente (triage completo o escalamiento por
  # recordatorios sin respuesta, ver Calendario::WelcomeBotFlowRunner#finish!
  # y Calendario::BotSessionReminderJob#escalate), un mensaje nuevo del mismo
  # contacto NO reinicia el triage si es el MISMO dia calendario (zona de la
  # cuenta, ej. "Bogota" -- nunca UTC del servidor). Si es un dia distinto,
  # SI se reinicia -- pedido explicito del usuario 2026-11-25: "cuando ya un
  # paciente escribe al dia siguiente, nuevamente le enviamos el bot de
  # triaje", reemplaza por completo la vieja feature separada
  # "paciente que regresa" (Calendario::ReturningAppointmentPromptListener,
  # eliminada). Si todavia no hay sesion activa, solo aplica cuando la
  # conversacion ya tiene asignado un agente Y alguna vez corrio una sesion
  # de bot (sin esto ultimo, una conversacion nueva atrapada en la carrera
  # de auto-asignacion -- ver WelcomeBotFlowRunner#start! -- se confunde con
  # una ya entregada y el bot nunca llega a arrancar).
  def already_handled_today?(conversation, message)
    return false if Calendario::BotSession.active.exists?(conversation: conversation)
    return false unless conversation.assignee_id.present? && Calendario::BotSession.exists?(conversation: conversation)

    !new_calendar_day?(conversation, message)
  end

  # Mismo patron que la vieja Calendario::ReturningAppointmentPromptListener#new_calendar_day? --
  # sin mensaje entrante anterior no hay "otro dia" con que comparar, asi
  # que no aplica (nunca reinicia solo porque "no hay historial").
  def new_calendar_day?(conversation, message)
    previous = conversation.messages.incoming.where.not(id: message.id).order(created_at: :desc).first
    return false if previous.blank?

    local_date(conversation, previous.created_at) != local_date(conversation, message.created_at)
  end

  def local_date(conversation, time)
    zone = conversation.account.reporting_timezone.presence || 'UTC'
    time.in_time_zone(zone).to_date
  end
end

# Corre periodicamente (ver config/schedule.yml) y aplica una cadencia de
# recordatorios configurable por flow (Calendario::WelcomeBotFlow#reminder_schedule,
# array de { "after_minutes" => N, "message" => "..." }) -- el ULTIMO
# elemento de la lista siempre escala (entrega la conversacion a un agente
# disponible), los anteriores son recordatorios simples.
#
# Un flow SIN reminder_schedule configurado (array vacio, el default de la
# columna) usa el comportamiento historico confirmado por el usuario: 1
# recordatorio a los 5 min repitiendo la pregunta actual, y si tampoco
# responde, escalamiento 20 min despues con escalation_message. Asi ningun
# flow existente cambia de comportamiento sin editarlo explicitamente.
#
# Idempotente por diseño -- cada sesion solo avanza de reminder_count N a
# N+1 una vez por corrida, usando last_prompted_at como el punto de
# referencia, asi que un atraso de Sidekiq que haga correr este job tarde no
# manda recordatorios de mas (ver mismo criterio que
# Calendario::Appointment#schedule_before_start_triggers).
class Calendario::BotSessionReminderJob < ApplicationJob
  queue_as :low

  FIRST_REMINDER_AFTER = 5.minutes
  ESCALATE_AFTER = 20.minutes

  DEFAULT_ESCALATION_MESSAGE = 'Hola, disculpa la demora. Un asesor te va a atender enseguida.'.freeze

  def perform
    Calendario::BotSession.active.find_each do |session|
      process(session)
    end
  end

  private

  def process(session)
    return if session.last_prompted_at.blank?

    schedule = effective_schedule(session.welcome_bot_flow)
    entry = schedule[session.reminder_count]
    return if entry.blank? || Time.current - session.last_prompted_at < entry[:after]

    last_entry = session.reminder_count == schedule.size - 1
    last_entry ? escalate(session, entry[:message]) : remind(session, entry[:message])
  end

  def effective_schedule(flow)
    configured = Array(flow.reminder_schedule)
    return default_schedule(flow) if configured.blank?

    configured.map { |entry| { after: entry['after_minutes'].to_i.minutes, message: entry['message'] } }
  end

  def default_schedule(flow)
    [
      { after: FIRST_REMINDER_AFTER, message: nil },
      { after: ESCALATE_AFTER, message: flow.escalation_message.presence || DEFAULT_ESCALATION_MESSAGE }
    ]
  end

  def remind(session, message)
    step = session.current_step_config
    return if step.blank?

    send_message(session, message.presence || reminder_prompt(step))
    session.update!(reminder_count: session.reminder_count + 1, last_prompted_at: Time.current)
  end

  def reminder_prompt(step)
    body = "¿Sigue ahí? #{step['ask']}"
    if step['buttons'].present?
      body += "\n\nSelecciona una opción de arriba."
    elsif step['options'].present?
      body += "\n\n#{Array(step['options']).join("\n")}"
    end
    body
  end

  # Entrega la conversacion a un humano igual que un triage completado
  # normalmente (ver Calendario::WelcomeBotFlowRunner#finish!): mensaje de
  # escalamiento + asignacion a un agente disponible de la bandeja + libera
  # enable_auto_assignment si no queda nadie mas en triage ahi.
  def escalate(session, message)
    send_message(session, message.presence || DEFAULT_ESCALATION_MESSAGE)

    conversation = session.conversation
    inbox = conversation.inbox
    Calendario::WelcomeBotAssignmentService.new(conversation: conversation).perform

    session.update!(status: 'handed_off')
    still_active = Calendario::BotSession.active
                                         .joins(:welcome_bot_flow)
                                         .where(calendario_welcome_bot_flows: { inbox_id: inbox.id })
                                         .where.not(conversation_id: conversation.id)
                                         .exists?
    inbox.update!(enable_auto_assignment: true) unless still_active
  end

  def send_message(session, body)
    session.conversation.messages.create!(
      account: session.account, inbox: session.conversation.inbox, message_type: :outgoing, content: body
    )
  end
end

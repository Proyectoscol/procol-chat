# Corre periodicamente (ver config/schedule.yml) y aplica la cadencia
# confirmada por el usuario: 2 recordatorios cada 5 min, y si tampoco
# responde al segundo, un tercer mensaje de escalamiento (editable por
# flujo, ver Calendario::WelcomeBotFlow#escalation_message) 20 min despues,
# que entrega la conversacion a un agente disponible -- pedido explicito del
# usuario para reemplazar el reset silencioso original. Idempotente por
# diseño -- cada sesion solo avanza de reminder_count N a N+1 una vez por
# corrida, usando last_prompted_at como el punto de referencia, asi que un
# atraso de Sidekiq que haga correr este job tarde no manda recordatorios de
# mas (ver mismo criterio que Calendario::Appointment#schedule_before_start_triggers).
class Calendario::BotSessionReminderJob < ApplicationJob
  queue_as :low

  FIRST_REMINDER_AFTER = 5.minutes
  SECOND_REMINDER_AFTER = 5.minutes
  ESCALATE_AFTER = 20.minutes

  DEFAULT_ESCALATION_MESSAGE = 'Hola, disculpa la demora. Un asesor te va a atender enseguida.'.freeze

  THRESHOLD_BY_REMINDER_COUNT = {
    0 => FIRST_REMINDER_AFTER, 1 => SECOND_REMINDER_AFTER, 2 => ESCALATE_AFTER
  }.freeze

  def perform
    Calendario::BotSession.active.find_each do |session|
      process(session)
    end
  end

  private

  def process(session)
    return if session.last_prompted_at.blank?

    threshold = THRESHOLD_BY_REMINDER_COUNT[session.reminder_count]
    return if threshold.blank? || Time.current - session.last_prompted_at < threshold

    session.reminder_count < 2 ? remind(session) : escalate(session)
  end

  def remind(session)
    step = session.current_step_config
    return if step.blank?

    body = "¿Sigue ahí? #{step['ask']}"
    body += "\n\n#{Array(step['options']).join("\n")}" if step['options'].present?
    create_private_note(session, body)
    session.update!(reminder_count: session.reminder_count + 1, last_prompted_at: Time.current)
  end

  # Entrega la conversacion a un humano igual que un triage completado
  # normalmente (ver Calendario::WelcomeBotFlowRunner#finish!): mensaje de
  # escalamiento + asignacion a un agente disponible de la bandeja + libera
  # enable_auto_assignment si no queda nadie mas en triage ahi.
  def escalate(session)
    message = session.welcome_bot_flow.escalation_message.presence || DEFAULT_ESCALATION_MESSAGE
    create_private_note(session, message)

    conversation = session.conversation
    inbox = conversation.inbox
    AutoAssignment::AgentAssignmentService.new(
      conversation: conversation, allowed_agent_ids: inbox.member_ids_with_assignment_capacity
    ).perform

    session.update!(status: 'handed_off')
    still_active = Calendario::BotSession.active
                                         .joins(:welcome_bot_flow)
                                         .where(calendario_welcome_bot_flows: { inbox_id: inbox.id })
                                         .where.not(conversation_id: conversation.id)
                                         .exists?
    inbox.update!(enable_auto_assignment: true) unless still_active
  end

  def create_private_note(session, body)
    session.conversation.messages.create!(
      account: session.account, inbox: session.conversation.inbox, private: true, message_type: :outgoing,
      content: "[BOT DE BIENVENIDA -- modo de prueba, nunca se envio un mensaje real]\n\n#{body}"
    )
  end
end

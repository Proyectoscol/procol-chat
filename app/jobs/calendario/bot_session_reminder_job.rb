# Corre periodicamente (ver config/schedule o cron, pendiente de agendar) y
# aplica la cadencia confirmada por el usuario: 2 recordatorios cada 5 min,
# reset a los 20 min del segundo. Idempotente por diseño -- cada sesion solo
# avanza de reminder_count N a N+1 una vez por corrida, usando
# last_prompted_at como el punto de referencia, asi que un atraso de
# Sidekiq que haga correr este job tarde no manda recordatorios de mas (ver
# mismo criterio que Calendario::Appointment#schedule_before_start_triggers).
class Calendario::BotSessionReminderJob < ApplicationJob
  queue_as :low

  FIRST_REMINDER_AFTER = 5.minutes
  SECOND_REMINDER_AFTER = 5.minutes
  RESET_AFTER = 20.minutes

  def perform
    Calendario::BotSession.active.find_each do |session|
      process(session)
    end
  end

  private

  def process(session)
    return if session.last_prompted_at.blank?

    elapsed = Time.current - session.last_prompted_at
    case session.reminder_count
    when 0 then remind(session) if elapsed >= FIRST_REMINDER_AFTER
    when 1 then remind(session) if elapsed >= SECOND_REMINDER_AFTER
    when 2 then reset(session) if elapsed >= RESET_AFTER
    end
  end

  def remind(session)
    step = session.current_step_config
    return if step.blank?

    body = "¿Sigue ahí? #{step['ask']}"
    body += "\n\n#{Array(step['options']).join("\n")}" if step['options'].present?
    session.conversation.messages.create!(
      account: session.account, inbox: session.conversation.inbox, private: true, message_type: :outgoing,
      content: "[BOT DE BIENVENIDA -- modo de prueba, nunca se envio un mensaje real]\n\n#{body}"
    )
    session.update!(reminder_count: session.reminder_count + 1, last_prompted_at: Time.current)
  end

  # No reactiva enable_auto_assignment ni termina la conversacion -- el
  # reset solo libera el "turno" del bot (el proximo mensaje de ese
  # contacto vuelve a pasar por el matching completo, ver
  # Calendario::WelcomeBotListener); si de verdad no queda nadie mas en
  # triage en esa bandeja, Calendario::WelcomeBotFlowRunner#finish!
  # reactiva la auto-asignacion cuando corresponda.
  def reset(session)
    session.update!(status: 'reset')
    inbox = session.conversation.inbox
    still_active = Calendario::BotSession.active
                                         .joins(:welcome_bot_flow)
                                         .exists?(calendario_welcome_bot_flows: { inbox_id: inbox.id })
    inbox.update!(enable_auto_assignment: true) unless still_active
  end
end

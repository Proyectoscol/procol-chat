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
    return unless Calendario::WelcomeBotFlow.exists?(inbox_id: message.inbox_id, active: true)
    return if restarting_an_already_assigned_conversation?(message.conversation)

    Calendario::WelcomeBotFlowRunner.new(conversation: message.conversation, message: message).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  private

  # Una vez entregada a un agente (triage completo o escalamiento por
  # recordatorios sin respuesta, ver Calendario::WelcomeBotFlowRunner#finish!
  # y Calendario::BotSessionReminderJob#escalate), un mensaje nuevo del mismo
  # contacto no debe reiniciar el triage desde cero -- ya es una conversacion
  # humana en curso. Si todavia no hay sesion activa, solo aplica cuando la
  # conversacion ya tiene asignado un agente Y alguna vez corrio una sesion
  # de bot (sin esto ultimo, una conversacion nueva atrapada en la carrera
  # de auto-asignacion -- ver WelcomeBotFlowRunner#start! -- se confunde con
  # una ya entregada y el bot nunca llega a arrancar).
  def restarting_an_already_assigned_conversation?(conversation)
    conversation.assignee_id.present? &&
      Calendario::BotSession.exists?(conversation: conversation) &&
      !Calendario::BotSession.active.exists?(conversation: conversation)
  end
end

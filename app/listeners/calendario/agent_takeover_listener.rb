# Pedido explicito del usuario 2026-11-27: si un agente humano ya esta
# respondiendo manualmente, el bot de bienvenida/triaje no debe seguir
# esperando la respuesta del paciente a SU propia pregunta en paralelo --
# ej. el paciente podria responder algo que el bot interpreta como
# respuesta a su pregunta vieja, en vez de a lo que el agente acaba de
# preguntar, o el bot podria reenviar un recordatorio/escalamiento encima
# de una conversacion que un humano ya esta atendiendo.
#
# Solo reacciona a un mensaje SALIENTE real (nunca nota privada, nunca un
# mensaje del propio bot -- el bot manda sus mensajes sin sender de tipo
# User, ver Calendario::WelcomeBotMessaging) de un AGENTE humano.
class Calendario::AgentTakeoverListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.outgoing? && !message.private? && message.sender.is_a?(User)

    session = Calendario::BotSession.active.find_by(conversation: message.conversation)
    return if session.blank?

    session.end!
    message.conversation.update!(assignee: message.sender) if message.conversation.assignee_id != message.sender_id
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end

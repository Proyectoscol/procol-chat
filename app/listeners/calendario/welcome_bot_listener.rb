class Calendario::WelcomeBotListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.incoming? && !message.private?
    return unless Calendario::WelcomeBotFlow.exists?(inbox_id: message.inbox_id, active: true)

    Calendario::WelcomeBotFlowRunner.new(message: message).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end

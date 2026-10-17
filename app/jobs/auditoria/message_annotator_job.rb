class Auditoria::MessageAnnotatorJob < ApplicationJob
  queue_as :low

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    Auditoria::MessageAnnotatorService.new(message: message).call
  end
end

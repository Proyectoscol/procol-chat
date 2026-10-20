class Auditoria::KeywordCategoryMatcherJob < ApplicationJob
  queue_as :low

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    Auditoria::KeywordCategoryMatcherService.new(
      messages: Message.where(id: message.id),
      categories: message.account.auditoria_categories
    ).call
  end
end

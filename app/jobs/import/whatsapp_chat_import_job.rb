# Un job por zip subido -- si uno falla (zip corrupto, bug), no afecta a
# los demas de la tanda.
class Import::WhatsappChatImportJob < ApplicationJob
  queue_as :low

  def perform(batch_id)
    batch = Import::WhatsappChatBatch.find_by(id: batch_id)
    return if batch.blank?

    batch.update!(status: :processing)
    Import::WhatsappChatImportService.new(batch: batch).perform
  rescue StandardError => e
    batch&.update!(status: :failed, error_message: e.message)
    ChatwootExceptionTracker.new(e, account: batch&.account).capture_exception
  end
end

class Calendario::AccountDataImportJob < ApplicationJob
  queue_as :low

  def perform(import_id)
    import = Calendario::AccountDataImport.find_by(id: import_id)
    return if import.blank?

    Calendario::AccountDataImportService.new(import: import).perform
  rescue StandardError => e
    import&.update!(status: :failed, error_message: e.message)
    ChatwootExceptionTracker.new(e, account: import&.account).capture_exception
  end
end

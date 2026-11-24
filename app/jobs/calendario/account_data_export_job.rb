class Calendario::AccountDataExportJob < ApplicationJob
  queue_as :low

  def perform(export_id)
    export = Calendario::AccountDataExport.find_by(id: export_id)
    return if export.blank?

    Calendario::AccountDataExportService.new(export: export).perform
  rescue StandardError => e
    export&.update!(status: :failed, error_message: e.message)
    ChatwootExceptionTracker.new(e, account: export&.account).capture_exception
  end
end

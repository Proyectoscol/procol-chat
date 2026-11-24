class Api::V1::Accounts::Calendario::AccountDataExportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    exports = Current.account.calendario_account_data_exports.order(created_at: :desc)
    render json: exports.map { |export| serialize(export) }
  end

  def create
    export = Current.account.calendario_account_data_exports.create!(created_by_id: Current.user.id)
    render json: serialize(export)
  end

  private

  def serialize(export)
    {
      id: export.id,
      status: export.status,
      error_message: export.error_message,
      manifest: export.manifest,
      download_url: export.completed? && export.export_file.attached? ? url_for(export.export_file) : nil,
      created_at: export.created_at
    }
  end

  def check_authorization
    authorize(:'calendario/account_data_exports')
  end
end

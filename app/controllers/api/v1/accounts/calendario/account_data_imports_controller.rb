class Api::V1::Accounts::Calendario::AccountDataImportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    imports = Current.account.calendario_account_data_imports.includes(:inbox).order(created_at: :desc)
    render json: imports.map { |import| serialize(import) }
  end

  def create
    render json: { error: 'import_file es obligatorio' }, status: :unprocessable_entity and return if params[:import_file].blank?
    render json: { error: 'inbox_id es obligatorio' }, status: :unprocessable_entity and return if params[:inbox_id].blank?

    import = Current.account.calendario_account_data_imports.create!(
      inbox_id: params[:inbox_id], created_by_id: Current.user.id
    )
    import.import_file.attach(params[:import_file])
    render json: serialize(import)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  def serialize(import)
    {
      id: import.id,
      status: import.status,
      error_message: import.error_message,
      stats: import.stats,
      inbox_id: import.inbox_id,
      inbox_name: import.inbox.name,
      created_at: import.created_at
    }
  end

  def check_authorization
    authorize(:'calendario/account_data_imports')
  end
end

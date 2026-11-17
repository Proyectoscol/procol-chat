class Api::V1::Accounts::Import::WhatsappChatBatchesController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    batches = Current.account.import_whatsapp_chat_batches.includes(:contact).order(created_at: :desc)
    render json: batches.map { |batch| serialize(batch) }
  end

  def create
    render json: { error: 'zip_file es obligatorio' }, status: :unprocessable_entity and return if params[:zip_file].blank?

    batch = Current.account.import_whatsapp_chat_batches.create!(batch_params.merge(created_by_id: Current.user.id))
    batch.zip_file.attach(params[:zip_file])
    render json: serialize(batch)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  def batch_params
    params.permit(:inbox_id, :us_sender_name, :phone_number, :original_filename)
  end

  def serialize(batch)
    {
      id: batch.id,
      status: batch.status,
      original_filename: batch.original_filename,
      phone_number: batch.phone_number,
      us_sender_name: batch.us_sender_name,
      error_message: batch.error_message,
      stats: batch.stats,
      contact_name: batch.contact&.name,
      created_at: batch.created_at
    }
  end

  def check_authorization
    authorize(:'import/whatsapp_chat_batches')
  end
end

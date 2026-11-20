class Api::V1::Accounts::Calendario::WaitlistEntriesController < Api::V1::Accounts::BaseController
  wrap_parameters :waitlist_entry, include: %i[contact_id professional_id service_id notes status]

  before_action :check_authorization
  before_action :fetch_entry, only: [:update, :destroy]

  def index
    entries = Current.account.calendario_waitlist_entries.includes(:contact, :professional, :service).pending
    entries = entries.for_professional(params[:professional_id]) if params[:professional_id].present?
    render json: entries.order(created_at: :asc).map { |entry| serialize(entry) }
  end

  # Para la alerta de "ya estuvo en lista de espera para este profesional y
  # servicio" en el formulario de agregar -- deliberadamente no reusa #index
  # (que solo trae pending, para la lista normal): aqui si importa el
  # historico completo (fulfilled/cancelled tambien cuentan como "ya estuvo
  # antes"), pero solo se necesita saber si existe, no traer los datos.
  def check_duplicate
    exists = Current.account.calendario_waitlist_entries.exists?(
      contact_id: params[:contact_id], professional_id: params[:professional_id], service_id: params[:service_id]
    )
    render json: { exists: exists }
  end

  def create
    entry = Current.account.calendario_waitlist_entries.create!(entry_params)
    render json: serialize(entry)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @entry.update!(entry_params)
    render json: serialize(@entry)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    @entry.destroy!
    head :no_content
  end

  private

  def fetch_entry
    @entry = Current.account.calendario_waitlist_entries.find(params[:id])
  end

  def entry_params
    params.require(:waitlist_entry).permit(:contact_id, :professional_id, :service_id, :notes, :status)
  end

  def serialize(entry)
    {
      id: entry.id, status: entry.status, notes: entry.notes, origin: entry.origin, created_at: entry.created_at,
      contact_id: entry.contact_id, contact_name: entry.contact.name, contact_phone_number: entry.contact.phone_number,
      professional_id: entry.professional_id, professional_name: entry.professional.name,
      service_id: entry.service_id, service_name: entry.service.name
    }
  end

  def check_authorization
    authorize(:'calendario/waitlist_entries')
  end
end

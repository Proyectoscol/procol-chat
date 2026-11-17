class Api::V1::Accounts::Calendario::ServicesController < Api::V1::Accounts::BaseController
  wrap_parameters :service, include: %i[name duration_minutes color active professional_ids kind included_sessions base_price]

  before_action :check_authorization
  before_action :fetch_service, only: [:update, :destroy]

  def index
    render json: Current.account.calendario_services.order(:name).map { |service| serialize(service) }
  end

  def create
    service = Current.account.calendario_services.create!(service_params.except(:professional_ids))
    service.professional_ids = service_params[:professional_ids] if service_params[:professional_ids]
    render json: serialize(service)
  end

  def update
    @service.update!(service_params.except(:professional_ids))
    @service.professional_ids = service_params[:professional_ids] if service_params[:professional_ids]
    render json: serialize(@service)
  end

  def destroy
    @service.destroy!
    head :no_content
  end

  private

  def fetch_service
    @service = Current.account.calendario_services.find(params[:id])
  end

  def service_params
    params.require(:service).permit(:name, :duration_minutes, :color, :active, :kind, :included_sessions,
                                     :base_price, professional_ids: [])
  end

  def serialize(service)
    {
      id: service.id, name: service.name, duration_minutes: service.duration_minutes,
      color: service.color, active: service.active, professional_ids: service.professional_ids,
      kind: service.kind, included_sessions: service.included_sessions, base_price: service.base_price
    }
  end

  def check_authorization
    authorize(:'calendario/services')
  end
end

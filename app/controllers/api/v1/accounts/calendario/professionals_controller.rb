class Api::V1::Accounts::Calendario::ProfessionalsController < Api::V1::Accounts::BaseController
  # Ver Auditoria::CategoriesController: sin esto, ActionController::ParamsWrapper
  # resuelve el hash envuelto contra un namespace equivocado.
  wrap_parameters :professional, include: %i[name active user_id specialty_id]

  before_action :check_authorization
  before_action :fetch_professional, only: [:update, :destroy]

  def index
    professionals = Current.account.calendario_professionals.includes(:specialty)
    professionals = professionals.where(specialty_id: params[:specialty_id]) if params[:specialty_id].present?
    render json: professionals.order(:name).map { |professional| serialize(professional) }
  end

  def create
    professional = Current.account.calendario_professionals.create!(professional_params)
    render json: serialize(professional)
  end

  def update
    @professional.update!(professional_params)
    render json: serialize(@professional)
  end

  def destroy
    @professional.destroy!
    head :no_content
  end

  private

  def fetch_professional
    @professional = Current.account.calendario_professionals.find(params[:id])
  end

  def professional_params
    params.require(:professional).permit(:name, :active, :user_id, :specialty_id)
  end

  def serialize(professional)
    {
      id: professional.id, name: professional.name, active: professional.active,
      user_id: professional.user_id, service_ids: professional.service_ids,
      specialty_id: professional.specialty_id, specialty_name: professional.specialty&.name
    }
  end

  def check_authorization
    authorize(:'calendario/professionals')
  end
end

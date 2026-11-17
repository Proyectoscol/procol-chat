class Api::V1::Accounts::Calendario::SpecialtiesController < Api::V1::Accounts::BaseController
  wrap_parameters :specialty, include: %i[name active]

  before_action :check_authorization
  before_action :fetch_specialty, only: [:update, :destroy]

  def index
    render json: Current.account.calendario_specialties.order(:name).map { |specialty| serialize(specialty) }
  end

  def create
    specialty = Current.account.calendario_specialties.create!(specialty_params)
    render json: serialize(specialty)
  end

  def update
    @specialty.update!(specialty_params)
    render json: serialize(@specialty)
  end

  def destroy
    @specialty.destroy!
    head :no_content
  end

  private

  def fetch_specialty
    @specialty = Current.account.calendario_specialties.find(params[:id])
  end

  def specialty_params
    params.require(:specialty).permit(:name, :active)
  end

  def serialize(specialty)
    { id: specialty.id, name: specialty.name, active: specialty.active }
  end

  def check_authorization
    authorize(:'calendario/specialties')
  end
end

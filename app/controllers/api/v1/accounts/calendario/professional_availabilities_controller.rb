class Api::V1::Accounts::Calendario::ProfessionalAvailabilitiesController < Api::V1::Accounts::BaseController
  wrap_parameters :availability, include: %i[weekdays start_time end_time starts_on ends_on active]

  before_action :check_authorization
  before_action :fetch_professional
  before_action :fetch_availability, only: [:destroy]

  def index
    render json: @professional.availabilities.order(:starts_on).map { |availability| serialize(availability) }
  end

  def create
    availability = @professional.availabilities.create!(availability_params)
    render json: serialize(availability)
  end

  def destroy
    @availability.destroy!
    head :no_content
  end

  private

  def fetch_professional
    @professional = Current.account.calendario_professionals.find(params[:professional_id])
  end

  def fetch_availability
    @availability = @professional.availabilities.find(params[:id])
  end

  def availability_params
    params.require(:availability).permit(:start_time, :end_time, :starts_on, :ends_on, :active, weekdays: [])
  end

  def serialize(availability)
    {
      id: availability.id, weekdays: availability.weekdays,
      start_time: availability.start_time.strftime('%H:%M'), end_time: availability.end_time.strftime('%H:%M'),
      starts_on: availability.starts_on, ends_on: availability.ends_on, active: availability.active
    }
  end

  def check_authorization
    authorize(:'calendario/professional_availabilities')
  end
end

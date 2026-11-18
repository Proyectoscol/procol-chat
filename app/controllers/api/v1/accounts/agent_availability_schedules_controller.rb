class Api::V1::Accounts::AgentAvailabilitySchedulesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :fetch_schedule, only: [:update, :destroy]

  def index
    @agent_availability_schedules = Current.account.agent_availability_schedules.order(starts_on: :desc)
  end

  def create
    @agent_availability_schedule = Current.account.agent_availability_schedules.new(
      schedule_params.merge(created_by_id: current_user.id)
    )
    @agent_availability_schedule.save!
  end

  def update
    @agent_availability_schedule.update!(schedule_params)
  end

  def destroy
    @agent_availability_schedule.destroy!
    head :ok
  end

  private

  def fetch_schedule
    @agent_availability_schedule = Current.account.agent_availability_schedules.find(params[:id])
  end

  def schedule_params
    params.permit(:user_id, :starts_on, :ends_on, :start_time, :end_time, :active, weekdays: [])
  end
end

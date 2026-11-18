class Api::V1::Accounts::Calendario::AppointmentEventTriggersController < Api::V1::Accounts::BaseController
  wrap_parameters :appointment_event_trigger,
                  include: %i[service_ids payer_kinds inbox_id trigger_kind target_status offset_minutes active
                              test_mode template_params]

  before_action :check_authorization
  before_action :fetch_trigger, only: [:update, :destroy]

  def index
    triggers = Current.account.calendario_appointment_event_triggers.includes(:inbox).order(:created_at)
    render json: triggers.map { |trigger| serialize(trigger) }
  end

  def create
    trigger = Current.account.calendario_appointment_event_triggers.create!(trigger_params)
    render json: serialize(trigger)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @trigger.update!(trigger_params)
    render json: serialize(@trigger)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    @trigger.destroy!
    head :no_content
  end

  private

  def fetch_trigger
    @trigger = Current.account.calendario_appointment_event_triggers.find(params[:id])
  end

  def trigger_params
    params.require(:appointment_event_trigger).permit(
      :inbox_id, :trigger_kind, :target_status, :offset_minutes, :active, :test_mode,
      service_ids: [], payer_kinds: [], template_params: {}
    )
  end

  def serialize(trigger)
    {
      id: trigger.id, trigger_kind: trigger.trigger_kind, target_status: trigger.target_status,
      offset_minutes: trigger.offset_minutes, active: trigger.active, test_mode: trigger.test_mode,
      service_ids: trigger.service_ids,
      services: trigger.services.map { |service| { id: service.id, name: service.name } },
      payer_kinds: trigger.payer_kinds,
      inbox_id: trigger.inbox_id, inbox_name: trigger.inbox.name,
      template_params: trigger.template_params
    }
  end

  def check_authorization
    authorize(:'calendario/appointment_event_triggers')
  end
end

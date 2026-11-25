class Api::V1::Accounts::Calendario::WelcomeBotFlowsController < Api::V1::Accounts::BaseController
  wrap_parameters :welcome_bot_flow,
                  include: %i[inbox_id name match_type match_value priority active steps escalation_message reminder_schedule]

  before_action :check_authorization
  before_action :fetch_flow, only: [:update, :destroy]

  def index
    flows = Current.account.calendario_welcome_bot_flows.includes(:inbox).order(priority: :desc, created_at: :asc)
    render json: flows.map { |flow| serialize(flow) }
  end

  def create
    flow = Current.account.calendario_welcome_bot_flows.create!(flow_params)
    render json: serialize(flow)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @flow.update!(flow_params)
    render json: serialize(@flow)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    @flow.destroy!
    head :no_content
  end

  private

  def fetch_flow
    @flow = Current.account.calendario_welcome_bot_flows.find(params[:id])
  end

  def flow_params
    params.require(:welcome_bot_flow).permit(
      :inbox_id, :name, :match_type, :match_value, :priority, :active, :escalation_message,
      steps: [
        :type, :ask, :ask_template, :ask_template_key, :empty_message, :empty_message_key,
        :waitlist_keyword, :ack_message, :ack_message_key, :content_sid, :on_unmatched,
        { options: [], buttons: [], if: [:step, :equals] }
      ],
      reminder_schedule: [:after_minutes, :message]
    )
  end

  def serialize(flow)
    {
      id: flow.id, name: flow.name, match_type: flow.match_type, match_value: flow.match_value,
      priority: flow.priority, active: flow.active, steps: flow.steps, escalation_message: flow.escalation_message,
      reminder_schedule: flow.reminder_schedule, inbox_id: flow.inbox_id, inbox_name: flow.inbox.name,
      template_warnings: flow.missing_template_warnings
    }
  end

  def check_authorization
    authorize(:'calendario/welcome_bot_flows')
  end
end

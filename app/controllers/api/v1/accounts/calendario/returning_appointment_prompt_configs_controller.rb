class Api::V1::Accounts::Calendario::ReturningAppointmentPromptConfigsController < Api::V1::Accounts::BaseController
  wrap_parameters :returning_appointment_prompt_config, include: %i[inbox_id active test_mode message_template_key ask_template options content_sid]

  before_action :check_authorization
  before_action :fetch_config, only: [:update]

  def index
    configs = Current.account.calendario_returning_appointment_prompt_configs.includes(:inbox)
    render json: configs.map { |config| serialize(config) }
  end

  def create
    config = Current.account.calendario_returning_appointment_prompt_configs.create!(config_params)
    render json: serialize(config)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    @config.update!(config_params.except(:inbox_id))
    render json: serialize(@config)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  def fetch_config
    @config = Current.account.calendario_returning_appointment_prompt_configs.find(params[:id])
  end

  def config_params
    params.require(:returning_appointment_prompt_config).permit(
      :inbox_id, :active, :test_mode, :message_template_key, :ask_template, :content_sid, options: []
    )
  end

  def serialize(config)
    {
      id: config.id, inbox_id: config.inbox_id, inbox_name: config.inbox.name,
      active: config.active, test_mode: config.test_mode,
      message_template_key: config.message_template_key, ask_template: config.ask_template,
      options: config.options, content_sid: config.content_sid
    }
  end

  def check_authorization
    authorize(:'calendario/returning_appointment_prompt_configs')
  end
end

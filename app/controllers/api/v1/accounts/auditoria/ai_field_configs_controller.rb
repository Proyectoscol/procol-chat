class Api::V1::Accounts::Auditoria::AiFieldConfigsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_field_config, only: [:update]

  def index
    render json: Current.account.auditoria_ai_field_configs.active.limit(5).map { |config| serialize(config) }
  end

  def update
    @field_config.update!(field_config_params)
    render json: serialize(@field_config)
  end

  private

  def fetch_field_config
    @field_config = Current.account.auditoria_ai_field_configs.find(params[:id])
  end

  def field_config_params
    params.require(:ai_field_config).permit(:title, :subtitle)
  end

  def serialize(config)
    { id: config.id, field_order: config.field_order, title: config.title, subtitle: config.subtitle }
  end

  def check_authorization
    authorize(:'auditoria/ai_field_configs')
  end
end

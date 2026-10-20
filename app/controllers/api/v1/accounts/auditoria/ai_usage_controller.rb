class Api::V1::Accounts::Auditoria::AiUsageController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :check_authorization

  def summary
    render json: {
      totals: Auditoria::AiUsageLogger.current_month_totals(Current.account),
      by_feature: totals_by_feature,
      limits: {
        monthly_cost_limit_usd: Current.account.auditoria_ai_monthly_cost_limit_usd,
        monthly_token_limit: Current.account.auditoria_ai_monthly_token_limit
      },
      models: {
        chat_model: Current.account.auditoria_chat_model,
        transcription_model: Current.account.auditoria_transcription_model
      }
    }
  end

  def index
    logs = Current.account.auditoria_ai_usage_logs.order(created_at: :desc).page(params[:page]).per(RESULTS_PER_PAGE)
    render json: { logs: logs.map { |log| serialize(log) }, total_count: logs.total_count }
  end

  def update_settings
    Current.account.update!(settings_params)
    render json: { success: true }
  end

  private

  def totals_by_feature
    Current.account.auditoria_ai_usage_logs
           .where(created_at: Time.current.beginning_of_month..)
           .group(:feature)
           .pluck(:feature, Arel.sql('SUM(cost_usd)'), Arel.sql('SUM(total_tokens)'))
           .to_h { |feature, cost, tokens| [feature, { cost_usd: cost, total_tokens: tokens }] }
  end

  def serialize(log)
    {
      id: log.id,
      feature: log.feature,
      model: log.model,
      conversation_id: log.conversation&.display_id,
      message_id: log.message_id,
      prompt_tokens: log.prompt_tokens,
      completion_tokens: log.completion_tokens,
      total_tokens: log.total_tokens,
      cost_usd: log.cost_usd,
      triggered_by: log.triggered_by,
      created_at: log.created_at.to_i
    }
  end

  def settings_params
    params.permit(
      :auditoria_ai_monthly_cost_limit_usd, :auditoria_ai_monthly_token_limit,
      :auditoria_chat_model, :auditoria_transcription_model
    )
  end

  def check_authorization
    authorize(:'auditoria/ai_usage')
  end
end

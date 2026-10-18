class Api::V1::Accounts::Auditoria::ConversationAnalysesController < Api::V1::Accounts::Conversations::BaseController
  before_action :check_authorization

  def show
    render json: {
      results: analysis&.results,
      analyzed_at: analysis&.analyzed_at&.to_i,
      needs_analysis: analyzer_service.needs_analysis?,
      field_configs: field_configs
    }
  end

  def create
    result = analyzer_service.perform

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_content
    else
      render json: { results: result[:message], analyzed_at: analysis&.analyzed_at }
    end
  end

  private

  def analyzer_service
    @analyzer_service ||= Auditoria::ConversationAnalyzerService.new(
      account: Current.account,
      conversation_display_id: @conversation.display_id
    )
  end

  def analysis
    @analysis ||= Auditoria::ConversationAnalysis.find_by(conversation_id: @conversation.id)
  end

  def field_configs
    Current.account.auditoria_ai_field_configs.active.limit(5).map do |config|
      { key: "field_#{config.field_order}", title: config.title, subtitle: config.subtitle }
    end
  end

  def check_authorization
    authorize(:'auditoria/conversation_analyses')
  end
end

class Api::V1::Accounts::Auditoria::ConversationAnalysesController < Api::V1::Accounts::Conversations::BaseController
  # Red de seguridad SOLO para un job que muere sin pasar por su ensure (ver
  # Auditoria::ConversationAnalyzerJob) -- 5 minutos era demasiado corto: una
  # conversacion con varias notas de voz pendientes de transcribir puede
  # tardar mas que eso en un job legitimo que sigue corriendo, haciendo que
  # el TTL expire solo y el frontend muestre "Analizar" de nuevo con el job
  # real todavia en curso (riesgo de un segundo job concurrente).
  PENDING_KEY_TTL = 30.minutes

  before_action :check_authorization

  def show
    render json: {
      results: analysis&.results,
      analyzed_at: analysis&.analyzed_at&.to_i,
      needs_analysis: analyzer_service.needs_analysis?,
      analyzing: pending?,
      error: Redis::Alfred.get(error_key),
      field_configs: field_configs
    }
  end

  def create
    # set(nx: true) es atomico (a diferencia de pending? + set separados) --
    # sin esto, 2 requests casi simultaneas pueden leer pending? como false
    # ambas antes de que cualquiera escriba la clave, encolando 2 jobs
    # (doble gasto de IA) para la misma conversacion.
    return render json: { queued: true } unless Redis::Alfred.set(pending_key, '1', nx: true, ex: PENDING_KEY_TTL)

    Redis::Alfred.delete(error_key)
    Auditoria::ConversationAnalyzerJob.perform_later(@conversation.id)
    render json: { queued: true }
  end

  private

  def pending?
    Redis::Alfred.get(pending_key).present?
  end

  def pending_key
    Auditoria::ConversationAnalyzerJob.pending_key(@conversation.id)
  end

  def error_key
    Auditoria::ConversationAnalyzerJob.error_key(@conversation.id)
  end

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

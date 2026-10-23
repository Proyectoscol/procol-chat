# Corre Auditoria::ConversationAnalyzerService en background -- la llamada a
# OpenAI puede tardar mas de lo que aguanta el proxy/gateway delante de la
# app, y una peticion sincrona que se corta a medio camino deja al frontend
# viendo "Analizando" para siempre aunque el backend si haya terminado y
# guardado el resultado. El estado "pendiente"/error vive en Redis (TTL
# como red de seguridad si el job muere sin pasar por el ensure) para que
# el controller lo consulte sin tocar el modelo.
class Auditoria::ConversationAnalyzerJob < ApplicationJob
  queue_as :low

  # pipeline_run_kind presente == esta conversacion es parte de una corrida
  # manual con seguimiento de progreso (ver Auditoria::PipelineRunTracker);
  # nil en el cron real y en "Analizar ahora" de una sola conversacion.
  def perform(conversation_id, triggered_by: :manual, pipeline_run_kind: nil)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    account = conversation.account
    result = Auditoria::ConversationAnalyzerService.new(
      account: account,
      conversation_display_id: conversation.display_id,
      triggered_by: triggered_by
    ).perform

    Redis::Alfred.set(error_key(conversation_id), result[:error], ex: 5.minutes) if result[:error]
    track_progress!(account, pipeline_run_kind, result) if pipeline_run_kind
  ensure
    Redis::Alfred.delete(pending_key(conversation_id))
  end

  def self.pending_key(conversation_id)
    format(Redis::RedisKeys::AUDITORIA_ANALYSIS_PENDING, id: conversation_id)
  end

  def self.error_key(conversation_id)
    format(Redis::RedisKeys::AUDITORIA_ANALYSIS_ERROR, id: conversation_id)
  end

  delegate :pending_key, :error_key, to: :class

  private

  # El limite de gasto se re-chequea aqui (no se confia en un codigo de
  # error estructurado) porque Auditoria::ConversationAnalyzerService solo
  # devuelve el mensaje ya traducido -- comparar contra el limite real es
  # mas robusto que comparar strings.
  def track_progress!(account, kind, result)
    if result[:error]
      spend_limited = !Auditoria::AiUsageLogger.within_limit?(account)
      Auditoria::PipelineRunTracker.increment_errored!(account, kind, spend_limited: spend_limited)
    else
      Auditoria::PipelineRunTracker.increment_processed!(account, kind)
    end
  end
end

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
    # Cualquier excepcion no manejada (red, fila duplicada, lo que sea) NO
    # debe dejar el contador de progreso sin tocar para siempre -- antes de
    # esto, una sola conversacion que reventara con una excepcion (no un
    # error ya manejado por el service, que si vuelve como {error:})
    # trababa la barra de progreso de la corrida entera por debajo del
    # 100% para siempre, sin forma de que el frontend supiera que paso. Se
    # cuenta como error y se vuelve a lanzar para que Sidekiq retry/dead-
    # queue siga funcionando exactamente igual que antes.
    unexpected_error = nil
    result = begin
      Auditoria::ConversationAnalyzerService.new(
        account: account,
        conversation_display_id: conversation.display_id,
        triggered_by: triggered_by
      ).perform
    rescue StandardError => e
      unexpected_error = e
      { error: e.message }
    end

    Redis::Alfred.set(error_key(conversation_id), result[:error], ex: 5.minutes) if result[:error]
    track_progress!(account, pipeline_run_kind, result) if pipeline_run_kind
    raise unexpected_error if unexpected_error
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

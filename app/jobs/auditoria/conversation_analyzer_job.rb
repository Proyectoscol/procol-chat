# Corre Auditoria::ConversationAnalyzerService en background -- la llamada a
# OpenAI puede tardar mas de lo que aguanta el proxy/gateway delante de la
# app, y una peticion sincrona que se corta a medio camino deja al frontend
# viendo "Analizando" para siempre aunque el backend si haya terminado y
# guardado el resultado. El estado "pendiente"/error vive en Redis (TTL
# como red de seguridad si el job muere sin pasar por el ensure) para que
# el controller lo consulte sin tocar el modelo.
class Auditoria::ConversationAnalyzerJob < ApplicationJob
  queue_as :low

  def perform(conversation_id, triggered_by: :manual)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    result = Auditoria::ConversationAnalyzerService.new(
      account: conversation.account,
      conversation_display_id: conversation.display_id,
      triggered_by: triggered_by
    ).perform

    Redis::Alfred.set(error_key(conversation_id), result[:error], ex: 5.minutes) if result[:error]
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
end

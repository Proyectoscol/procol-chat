# Unico punto de verdad para "que conversaciones necesitan analisis, sin
# limite de tiempo" -- usado tanto por Auditoria::BacklogEstimateService
# como por Auditoria::DailyConversationAnalysisSchedulerJob (modo
# unbounded:), para que el estimado y la corrida real cuenten exactamente
# lo mismo. Misma logica que Auditoria::ConversationAnalyzerService#
# needs_analysis? (sin analisis previo, o mensaje mas nuevo que
# analyzed_at) pero evaluada para TODA la cuenta de una sola vez via SQL,
# en vez de conversacion por conversacion.
class Auditoria::BacklogCandidateFinder
  def self.conversation_ids(account)
    account.conversations
           .joins(:messages)
           .where(messages: { message_type: [:incoming, :outgoing] })
           .group('conversations.id')
           .having(
             'MAX(messages.created_at) > COALESCE(' \
             '(SELECT analyzed_at FROM auditoria_conversation_analyses WHERE conversation_id = conversations.id), ' \
             "'-infinity')"
           )
           .pluck(:id)
  end
end

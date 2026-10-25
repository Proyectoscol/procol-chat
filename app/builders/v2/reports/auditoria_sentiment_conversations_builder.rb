# Conversaciones con un sentimiento puntual en un bucket de la grafica de
# tendencia, para el click-to-detail de V2::Reports::AuditoriaSentimentTimeseriesBuilder.
# Mismo patron que AuditoriaCategoryConversationsBuilder/
# AuditoriaAdvisorConversationsBuilder, cambiando el filtro de categoria por
# sentiment + los mismos ejes de asesor/equipo/bandeja del builder de tendencia.
class V2::Reports::AuditoriaSentimentConversationsBuilder
  include V2::Reports::Concerns::AuditoriaSentimentScoping

  pattr_initialize [:account!, :params!]

  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 25
  SENTIMENTS = %w[positive neutral negative].freeze

  def build
    conversations = paginated_conversations.to_a
    serializer = V2::Reports::DrilldownRecordSerializer.new(account, nil, false, conversations)
    {
      meta: { current_page: current_page, per_page: per_page, total_count: paginated_conversations.total_count },
      payload: conversations.map do |conversation|
        analysis = analysis_by_conversation_id(conversations)[conversation.id]
        serializer.serialize(conversation).merge(sentiment: analysis&.first, sentiment_reason: analysis&.second)
      end
    }
  end

  private

  # Sin sentiment puntual (clic en la grafica, mezcla los 3), cada tarjeta
  # necesita mostrar a cual le toco -- se resuelve aparte del filtro de
  # #base_conversation_ids para no acoplar la serializacion a ese query.
  # Acotado a las conversaciones YA paginadas (como mucho per_page), nunca a
  # filtered_conversation_ids completo -- ese universo puede ser decenas de
  # miles de ids en un rango largo, y aqui solo se necesita el sentiment de
  # la pagina actual.
  def analysis_by_conversation_id(conversations)
    Auditoria::ConversationAnalysis
      .where(conversation_id: conversations.map(&:id))
      .pluck(:conversation_id, :sentiment, :sentiment_reason)
      .to_h { |conversation_id, sentiment, sentiment_reason| [conversation_id, [sentiment, sentiment_reason]] }
  end

  def paginated_conversations
    @paginated_conversations ||= account.conversations
                                        .where(id: filtered_conversation_ids)
                                        .includes(:assignee, :contact, :inbox)
                                        .order(last_activity_at: :desc)
                                        .page(current_page)
                                        .per(per_page)
  end

  # Sin sentiment puntual (clic en la grafica, que no distingue por linea),
  # trae conversaciones de CUALQUIERA de los 3 -- mismo criterio "sin filtro
  # = todos" que category_ids en AuditoriaCategoryConversationsBuilder.
  def sentiment_filter
    params[:sentiment].presence || SENTIMENTS
  end

  def current_page
    [params[:page].to_i, DEFAULT_PAGE].max
  end

  def per_page
    DEFAULT_PER_PAGE
  end
end

# Conversaciones con un sentimiento puntual en un bucket de la grafica de
# tendencia, para el click-to-detail de V2::Reports::AuditoriaSentimentTimeseriesBuilder.
# Mismo patron que AuditoriaCategoryConversationsBuilder/
# AuditoriaAdvisorConversationsBuilder, cambiando el filtro de categoria por
# sentiment + los mismos ejes de asesor/equipo/bandeja del builder de tendencia.
class V2::Reports::AuditoriaSentimentConversationsBuilder
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
        serializer.serialize(conversation).merge(sentiment: sentiment_by_conversation_id(conversations)[conversation.id])
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
  def sentiment_by_conversation_id(conversations)
    Auditoria::ConversationAnalysis
      .where(conversation_id: conversations.map(&:id))
      .pluck(:conversation_id, :sentiment).to_h
  end

  def paginated_conversations
    @paginated_conversations ||= account.conversations
                                        .where(id: filtered_conversation_ids)
                                        .includes(:assignee, :contact, :inbox)
                                        .order(last_activity_at: :desc)
                                        .page(current_page)
                                        .per(per_page)
  end

  def filtered_conversation_ids
    @filtered_conversation_ids ||= begin
      ids = base_conversation_ids
      ids &= advisor_scoped_conversation_ids if advisor_scoped?
      ids
    end
  end

  def base_conversation_ids
    @base_conversation_ids ||= begin
      scope = Auditoria::ConversationAnalysis
              .where(account_id: account.id, sentiment: sentiment)
              .joins(:conversation)
              .where(conversations: { created_at: timestamp_range })
              .where.not(conversation_id: excluded_conversation_ids)
      scope = scope.where(conversations: { inbox_id: inbox_id }) if inbox_id.present?
      scope.pluck(:conversation_id)
    end
  end

  def timestamp_range
    Time.zone.at(params[:since].to_i)..Time.zone.at(params[:until].to_i)
  end

  def excluded_conversation_ids
    account.conversations.tagged_with(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE).ids
  end

  def advisor_scoped?
    user_id.present? || team_id.present?
  end

  def advisor_scoped_conversation_ids
    advisor_user_id_by_conversation_id.select { |_conversation_id, advisor_id| target_user_ids.include?(advisor_id) }.keys
  end

  def target_user_ids
    @target_user_ids ||= user_id.present? ? [user_id.to_i] : TeamMember.where(team_id: team_id).pluck(:user_id)
  end

  def advisor_user_id_by_conversation_id
    source_column = Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES
    @advisor_user_id_by_conversation_id ||= account.messages
                                                   .where(conversation_id: base_conversation_ids)
                                                   .where("#{source_column}->>'auditoria_source_user_id' IS NOT NULL")
                                                   .pluck(:conversation_id, Arel.sql("#{source_column}->>'auditoria_source_user_id'"))
                                                   .to_h.transform_values(&:to_i)
  end

  # Sin sentiment puntual (clic en la grafica, que no distingue por linea),
  # trae conversaciones de CUALQUIERA de los 3 -- mismo criterio "sin filtro
  # = todos" que category_ids en AuditoriaCategoryConversationsBuilder.
  def sentiment
    params[:sentiment].presence || SENTIMENTS
  end

  def user_id
    params[:user_id]
  end

  def team_id
    params[:team_id]
  end

  def inbox_id
    params[:inbox_id]
  end

  def current_page
    [params[:page].to_i, DEFAULT_PAGE].max
  end

  def per_page
    DEFAULT_PER_PAGE
  end
end

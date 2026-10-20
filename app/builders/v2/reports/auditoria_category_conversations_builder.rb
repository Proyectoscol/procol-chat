# Conversaciones con una categoria puntual, para el click-to-detail del
# reporte por categoria. Mismo patron que AuditoriaAdvisorConversationsBuilder,
# cambiando el filtro por advisor_id por un join a auditoria_category_mentions.
class V2::Reports::AuditoriaCategoryConversationsBuilder
  pattr_initialize [:account!, :params!]

  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 25

  def build
    conversations = paginated_conversations.to_a
    representative_messages = representative_messages_by_conversation_id(conversations)
    records = conversations.map { |conversation| representative_messages[conversation.id] || conversation }
    serializer = V2::Reports::DrilldownRecordSerializer.new(account, nil, false, records)
    {
      meta: { current_page: current_page, per_page: per_page, total_count: paginated_conversations.total_count },
      payload: records.map { |record| serializer.serialize(record) }
    }
  end

  private

  # Para categorias de palabra clave, cada tarjeta debe abrir el mensaje
  # puntual que disparo el match, no solo la conversacion -- se toma la
  # mencion con el message_id mas alto (el mas reciente, ya que los ids son
  # seriales) por conversacion. Las categorias de IA no tienen message_id
  # (el LLM solo reporta el dia, no un mensaje puntual -- ver
  # Auditoria::ConversationAnalyzerCategoryMatching#sync_ai_categories!), asi
  # que esas conversaciones quedan sin representante y la tarjeta cae de
  # vuelta a la conversacion completa (ver #build).
  def representative_messages_by_conversation_id(conversations)
    scope = Auditoria::CategoryMention
            .where(conversation_id: conversations.map(&:id), category_id: category_ids_for_filter)
            .where.not(message_id: nil)
    scope = scope.where(occurred_on: range) if range
    latest_message_ids = scope.group(:conversation_id).maximum(:message_id)
    Message.where(id: latest_message_ids.values).index_by(&:conversation_id)
  end

  def paginated_conversations
    @paginated_conversations ||= scoped_conversations
                                 .includes(:assignee, :contact, :inbox)
                                 .order(last_activity_at: :desc)
                                 .page(current_page)
                                 .per(per_page)
  end

  # .distinct: a diferencia de la fase de asesores (join 1-a-1), aqui una
  # conversacion puede tener varias filas de mencion para la misma categoria
  # (una por mensaje que matchea, o una por dia detectado por IA).
  def scoped_conversations
    scope = account.conversations
                   .joins(:auditoria_category_mentions)
                   .where(auditoria_category_mentions: { category_id: category_ids_for_filter })
                   .distinct
    scope = scope.where(auditoria_category_mentions: { occurred_on: range }) if range
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope
  end

  def range
    return unless params[:since].present? && params[:until].present?

    Time.zone.at(params[:since].to_i).to_date..Time.zone.at(params[:until].to_i).to_date
  end

  # Si category_id es una categoria padre (ej. "Competencia"), el drilldown
  # debe incluir conversaciones marcadas con CUALQUIERA de sus subcategorias
  # -- el padre nunca matchea por si mismo (ver Auditoria::Category.leaf).
  def category_ids_for_filter
    @category_ids_for_filter ||= begin
      category = account.auditoria_categories.find_by(id: category_id)
      category.present? ? [category.id] + category.descendant_ids : [category_id]
    end
  end

  def category_id
    params[:category_id]
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

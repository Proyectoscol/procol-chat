# Conversaciones con una categoria puntual, para el click-to-detail del
# reporte por categoria. Mismo patron que AuditoriaAdvisorConversationsBuilder,
# cambiando el filtro por advisor_id por un join a auditoria_category_mentions.
class V2::Reports::AuditoriaCategoryConversationsBuilder
  pattr_initialize [:account!, :params!]

  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 25

  def build
    conversations = paginated_conversations.to_a
    serializer = V2::Reports::DrilldownRecordSerializer.new(account, nil, false, conversations)
    {
      meta: { current_page: current_page, per_page: per_page, total_count: paginated_conversations.total_count },
      payload: conversations.map { |conversation| serializer.serialize(conversation) }
    }
  end

  private

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
                   .where(auditoria_category_mentions: { category_id: category_id })
                   .distinct
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope
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

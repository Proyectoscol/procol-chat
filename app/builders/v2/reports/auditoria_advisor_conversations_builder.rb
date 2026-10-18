# Conversaciones de un asesor puntual dentro del rango del reporte (ver
# V2::Reports::AuditoriaAdvisorSummaryBuilder), para el click-to-detail del
# reporte por asesor. Misma exclusion de conversaciones "auditoria-
# multiple-asesor" que el resumen, asi el detalle nunca muestra algo que el
# resumen excluyo.
class V2::Reports::AuditoriaAdvisorConversationsBuilder
  pattr_initialize [:account!, :params!]

  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 25

  def build
    conversations = paginated_conversations.to_a
    serializer = build_serializer(conversations)
    {
      meta: { current_page: current_page, per_page: per_page, total_count: paginated_conversations.total_count },
      # DrilldownRecordSerializer#serialize_conversation es privado -- solo
      # el publico #serialize, que la despacha para cualquier objeto que no
      # sea Message/ReportingEvent (nuestro caso: Conversation).
      payload: conversations.map { |conversation| serializer.serialize(conversation) }
    }
  end

  private

  # metric/use_business_hours no los usa serialize_conversation -- solo
  # importan para las ramas de reporting_events que esta cuenta no usa. Le
  # pasamos las conversaciones ya cargadas para que precargue en bloque el
  # ultimo mensaje de cada una (preview en la tarjeta), en vez de una query
  # por conversacion.
  def build_serializer(conversations)
    V2::Reports::DrilldownRecordSerializer.new(account, nil, false, conversations)
  end

  def paginated_conversations
    @paginated_conversations ||= account.conversations
                                        .where(id: conversation_ids)
                                        .includes(:assignee, :contact, :inbox)
                                        .order(last_activity_at: :desc)
                                        .page(current_page)
                                        .per(per_page)
  end

  def conversation_ids
    scope = account.messages.where(created_at: range)
                   .where("#{Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES}->>'auditoria_source_user_id' = ?",
                          user_id.to_s)
                   .where.not(conversation_id: excluded_conversation_ids)
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope.reorder(nil).distinct.pluck(:conversation_id)
  end

  def excluded_conversation_ids
    account.conversations.tagged_with(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE).ids
  end

  def user_id
    params[:user_id]
  end

  def inbox_id
    params[:inbox_id]
  end

  def range
    Time.zone.at(params[:since].to_i)..Time.zone.at(params[:until].to_i)
  end

  def current_page
    [params[:page].to_i, DEFAULT_PAGE].max
  end

  def per_page
    DEFAULT_PER_PAGE
  end
end

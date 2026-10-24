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
    payload = conversations.each_index.map do |index|
      serializer.serialize(records[index]).merge(match_reasons: match_reasons_for(conversations[index]))
    end
    {
      meta: { current_page: current_page, per_page: per_page, total_count: paginated_conversations.total_count },
      payload: payload
    }
  end

  private

  # Palabra clave: reconstruye en el momento cual(es) termino(s) configurado(s)
  # matchean el texto del mensaje (igual que AuditoriaCategoryTermsBuilder,
  # pero por mensaje puntual en vez de contar). IA: no hay texto que
  # re-evaluar -- se lee el reason ya guardado por
  # ConversationAnalyzerCategoryMatching (nil para menciones creadas antes
  # de ese campo, mismo criterio "no retroactivo" del resto del proyecto).
  def match_reasons_for(conversation)
    mentions = relevant_mentions_by_conversation_id[conversation.id] || []
    mentions.flat_map { |mention| reasons_for_mention(mention) }.uniq
  end

  def relevant_mentions_by_conversation_id
    @relevant_mentions_by_conversation_id ||= begin
      scope = Auditoria::CategoryMention.where(conversation_id: paginated_conversations.map(&:id), category_id: category_ids_for_filter)
      scope = scope.where(occurred_on: range) if range
      # Sin esto, el drilldown filtrado por un termino especifico (click en
      # TermsBreakdownList.vue) seguia mostrando razones de TODOS los
      # terminos que matchearon esa conversacion, no solo el que el usuario
      # clickeo -- igual que ya hace scoped_conversations.
      scope = scope.where(message_id: message_ids_matching_term) if term.present?
      scope.includes(:category, message: :attachments).group_by(&:conversation_id)
    end
  end

  def reasons_for_mention(mention)
    return [mention.reason].compact if mention.message_id.nil?

    matched_terms_for(mention)
  end

  def matched_terms_for(mention)
    return [] if mention.message.blank?

    text = mention.message.content_for_llm
    mention.category.search_terms_list.select { |term| text.match?(Auditoria::Category.term_regex(term)) }
  end

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
    # Mismo motivo que relevant_mentions_by_conversation_id: si el usuario
    # filtro por un termino puntual, el mensaje representativo debe ser uno
    # que de verdad contenga ese termino, no el mensaje mas reciente de
    # CUALQUIER termino de la categoria.
    scope = scope.where(message_id: message_ids_matching_term) if term.present?
    latest_message_ids = scope.group(:conversation_id).maximum(:message_id)
    Message.where(id: latest_message_ids.values).includes(conversation: %i[assignee contact inbox]).index_by(&:conversation_id)
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
    scope = scope.where(auditoria_category_mentions: { message_id: message_ids_matching_term }) if term.present?
    scope
  end

  # Mismo alcance que AuditoriaCategoryTermsBuilder#count_for_term: solo
  # revisa `content`, no transcripciones de audio -- limitacion ya existente
  # en ese builder, se mantiene igual aqui por consistencia.
  def message_ids_matching_term
    mention_message_ids = Auditoria::CategoryMention.where(category_id: category_ids_for_filter).where.not(message_id: nil).pluck(:message_id)
    Message.where(id: mention_message_ids).where('content ~* ?', Auditoria::Category.term_pattern(term)).ids
  end

  def term
    params[:term]
  end

  def range
    return unless params[:since].present? && params[:until].present?

    Time.zone.at(params[:since].to_i).to_date..Time.zone.at(params[:until].to_i).to_date
  end

  # Si category_id es una categoria padre (ej. "Competencia"), el drilldown
  # debe incluir conversaciones marcadas con CUALQUIERA de sus subcategorias
  # -- el padre nunca matchea por si mismo (ver Auditoria::Category.leaf).
  # category_ids (plural) es la alternativa usada por el clic en la
  # grafica de tiempo: ahi ya son ids de categorias HOJA (las unicas que se
  # pueden graficar), asi que no hace falta expandir a descendientes --
  # solo se filtran por visibilidad antes de usarlas.
  def category_ids_for_filter
    @category_ids_for_filter ||= if requested_category_ids.present?
                                   visible_requested_categories.map(&:id)
                                 else
                                   category_ids_for_single_filter
                                 end
  end

  def visible_requested_categories
    account.auditoria_categories.where(id: requested_category_ids).select { |category| category_visible?(category) }
  end

  def requested_category_ids
    Array(params[:category_ids]).map(&:to_i).presence
  end

  def category_ids_for_single_filter
    category = account.auditoria_categories.find_by(id: category_id)
    if category.present? && !category_visible?(category)
      []
    elsif category.present?
      # Igual que el summary builder: un hijo cuyo scope de inbox ya no
      # cubre al admin restringido actual no debe aparecer en el drilldown
      # del padre, aunque sus menciones viejas (no retroactivas, ver
      # Auditoria::Category#inbox_ids_within_parent_scope) sigan existiendo.
      visible_descendant_ids = category.subcategories.select { |child| category_visible?(child) }.map(&:id)
      [category.id] + visible_descendant_ids
    else
      [category_id]
    end
  end

  # inbox_id llega forzado a los inboxes permitidos para un admin restringido
  # -- pedir el drilldown de una categoria fuera de su scope no debe devolver
  # conversaciones, igual que ya no aparece en Settings > Categories.
  def category_visible?(category)
    return true if inbox_id.blank?

    Array(inbox_id).map(&:to_i).any? { |id| category.applies_to_inbox?(id) }
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

  # Override opcional -- el export CSV (sin paginar de verdad) pide un
  # per_page grande explicito; el drawer paginado normal nunca lo manda y
  # cae al default de siempre.
  def per_page
    requested = params[:per_page].to_i
    requested.positive? ? requested : DEFAULT_PER_PAGE
  end
end

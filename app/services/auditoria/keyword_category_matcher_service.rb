# Un solo metodo para dos casos de uso, nunca se duplica el SQL de matching:
#   - Tiempo real (Auditoria::KeywordCategoryMatcherJob): messages = los
#     mensajes NUEVOS de una conversacion, categories = todas las categorias
#     keyword de la cuenta.
#   - Backfill (Auditoria::KeywordCategoryBackfillJob): messages = TODOS los
#     mensajes historicos de la cuenta, categories = la UNA categoria recien
#     creada/editada.
# occurred_on viene del created_at real de cada mensaje (zona Bogota, ver
# nota de timezone en auditoria_advisor_summary_builder.rb) -- el backfill
# conserva fechas historicas reales, nunca "hoy".
class Auditoria::KeywordCategoryMatcherService
  pattr_initialize [:messages!, :categories!]

  def call
    # find_each no aplica -- maximo 10 categorias por cuenta
    # (Auditoria::Category::MAX_CATEGORIES_PER_ACCOUNT), no una tabla grande.
    # rubocop:disable Rails/FindEach
    # .leaf: una categoria "padre" (ej. "Competencia") es solo una
    # agrupacion visual en el reporte -- aunque tuviera search_terms
    # sobrantes de antes de ganar subcategorias, nunca debe matchear por si
    # misma (ver Auditoria::Category.leaf).
    categories.active.leaf.where(match_type: :keyword).each { |category| match_category(category) }
    # rubocop:enable Rails/FindEach
  end

  private

  def match_category(category)
    terms = category.search_terms_list
    return if terms.blank?

    rows = (text_rows(terms, category) + transcript_rows(terms, category)).uniq { |row| row[:message_id] }
    return if rows.blank?

    rows = rows.map { |row| row.merge(category_id: category.id, created_at: Time.current) }
    # insert_all respeta el indice unique parcial [message_id, category_id]
    # -- re-correr el backfill o reintentar el job nunca duplica filas.
    # rubocop:disable Rails/SkipsModelValidations
    Auditoria::CategoryMention.insert_all(rows)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Mensajes con texto propio -- SQL directo sobre content, como antes.
  def text_rows(terms, category)
    patterns = terms.map { |term| Auditoria::Category.term_pattern(term) }
    candidate_messages(category).where('content ~* ANY(ARRAY[?])', patterns)
                                .pluck(:id, :account_id, :conversation_id, :created_at)
                                .map { |id, account_id, conversation_id, created_at| row_for(id, account_id, conversation_id, created_at) }
  end

  # Notas de voz: el texto transcrito vive en attachments.meta['transcribed_text']
  # (ver Auditoria::AudioTranscriptionService), nunca en content -- content
  # queda en blanco para estos mensajes, asi que sin este chequeo una mencion
  # dicha solo por voz (ej. el cliente dice "CX-5" en un audio) nunca entra a
  # auditoria_category_mentions aunque el termino este bien configurado. No
  # se puede filtrar por SQL puro contra el jsonb sin duplicar el regex en
  # dos dialectos distintos, asi que el universo ya viene acotado por SQL
  # (solo audio + sin texto propio) y el regex final corre en Ruby.
  def transcript_rows(terms, category)
    regexes = terms.map { |term| Auditoria::Category.term_regex(term) }
    audio_candidate_messages(category).filter_map { |message| transcript_row(message, regexes) }
  end

  def transcript_row(message, regexes)
    transcript = audio_transcript_for(message)
    return if transcript.blank?
    return unless regexes.any? { |regex| transcript.match?(regex) }

    row_for(message.id, message.account_id, message.conversation_id, message.created_at)
  end

  def audio_transcript_for(message)
    message.attachments.find { |a| a.file_type == 'audio' }&.meta&.dig('transcribed_text')
  end

  def candidate_messages(category)
    scope = messages.where(message_type: [:incoming, :outgoing])
    return scope if category.scoped_to_all_inboxes?

    scope.joins(:conversation).where(conversations: { inbox_id: category.inbox_ids })
  end

  # Subquery (IN) en vez de joins(:attachments)+distinct a proposito:
  # messages.content_attributes es json (no jsonb, sin operador de
  # igualdad) -- un SELECT DISTINCT sobre messages.* revienta en Postgres
  # con "could not identify an equality operator for type json". El join
  # solo serviria para evitar filas repetidas si un mensaje tuviera mas de
  # un adjunto de audio; el IN evita el problema de raiz sin necesitar
  # distinct para nada.
  def audio_candidate_messages(category)
    candidate_messages(category).where(content: [nil, ''])
                                .where(id: Attachment.where(file_type: :audio).select(:message_id))
                                .includes(:attachments)
  end

  def row_for(message_id, account_id, conversation_id, created_at)
    { message_id: message_id, account_id: account_id, conversation_id: conversation_id, occurred_on: created_at.to_date }
  end
end

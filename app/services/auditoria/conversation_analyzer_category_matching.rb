# Extraido de Auditoria::ConversationAnalyzerService (Metrics/ClassLength) --
# todo lo relacionado a categorias configurables de tipo :ai: el schema
# dinamico, las instrucciones de prompt, y la sincronizacion de menciones
# por (categoria, dia) contra auditoria_category_mentions.
module Auditoria::ConversationAnalyzerCategoryMatching
  private

  def category_instructions
    return '' if active_ai_categories.blank?

    <<~INSTRUCTIONS

      Ademas, evalua si la conversacion aplica a alguna de estas categorias configuradas (puede aplicar a varias, a ninguna, o a todas). Usa los marcadores "Fecha:" de la conversacion para reportar en que dia(s) exactos detectaste cada categoria que aplique:
      #{category_list}
    INSTRUCTIONS
  end

  def category_list
    active_ai_categories.map { |c| c.instructions.present? ? "- #{c.title}: #{c.instructions}" : "- #{c.title}" }.join("\n")
  end

  # Verbatim del DSL verificado contra ruby_llm-schema 0.3.0 -- no se puede
  # heredar/extender Auditoria::ConversationAnalyzerSchema (RubyLLM::Schema
  # .create siempre arranca de Class.new(RubyLLM::Schema), no de una clase
  # padre custom), asi que los 5 field_N se repiten aqui a proposito.
  # rubocop:disable Metrics/MethodLength
  def schema
    return Auditoria::ConversationAnalyzerSchema if active_ai_categories.blank?

    category_titles = active_ai_categories.pluck(:title)
    RubyLLM::Schema.create do
      string :field_1, description: 'Respuesta a la tarea 1 solicitada en las instrucciones.'
      string :field_2, description: 'Respuesta a la tarea 2 solicitada en las instrucciones.'
      string :field_3, description: 'Respuesta a la tarea 3 solicitada en las instrucciones.'
      string :field_4, description: 'Respuesta a la tarea 4 solicitada en las instrucciones.'
      string :field_5, description: 'Respuesta a la tarea 5 solicitada en las instrucciones.'
      string :sentiment, enum: %w[positive neutral negative],
                         description: 'Sentimiento general del cliente a lo largo de toda la conversacion.'
      string :sentiment_reason,
             description: 'Explica brevemente (1-2 frases) en que parte(s) de la conversacion se basa esa clasificacion de sentimiento.'
      array :categories,
            description: 'Solo las categorias configuradas que SI aplican a esta conversacion. ' \
                         'No incluir categorias que no aplican.' do
        object do
          string :category, enum: category_titles, description: 'Titulo exacto de la categoria configurada.'
          array :dates, of: :string,
                        description: 'Dias (formato AAAA-MM-DD, tomados de los marcadores "Fecha:" de la conversacion) ' \
                                     'en que se detecto esta categoria.'
          string :reason, description: 'Frase corta explicando por que esta conversacion aplica a esta categoria.'
        end
      end
    end
  end
  # rubocop:enable Metrics/MethodLength

  # .leaf: una categoria agrupadora (ej. "Competencia") nunca se ofrece
  # como opcion clasificable al LLM -- solo sus subcategorias, que son las
  # que de verdad tienen instructions (ver Auditoria::Category.leaf).
  def active_ai_categories
    @active_ai_categories ||= account.auditoria_categories.active.leaf.where(match_type: :ai)
                                     .where("inbox_ids = '{}' OR inbox_ids @> ARRAY[?]::integer[]", conversation.inbox_id)
                                     .order(:title)
  end

  # Diffea por (categoria, dia) -- no solo por categoria -- contra las filas
  # de IA EXISTENTES de esta conversacion (message_id: nil; nunca toca filas
  # de palabra clave, son poblaciones independientes de la misma tabla). El
  # reason solo se guarda al CREAR una fila -- si un (categoria, dia) ya
  # existia, su reason original se queda igual aunque la redaccion de este
  # analisis sea distinta (mismo criterio "no retroactivo" del resto de
  # campos de IA en este sistema).
  def sync_ai_categories!(returned_categories)
    return if active_ai_categories.blank?

    reason_by_pair = wanted_category_date_reasons(returned_categories)
    wanted = reason_by_pair.keys
    existing = existing_ai_category_date_pairs

    create_category_mentions(wanted - existing, reason_by_pair)
    destroy_category_mentions(existing - wanted)
  end

  def wanted_category_date_reasons(returned_categories)
    title_to_id = active_ai_categories.pluck(:title, :id).to_h
    Array(returned_categories).each_with_object({}) do |entry, reason_by_pair|
      category_date_reasons_for(entry, title_to_id).each { |pair, reason| reason_by_pair[pair] = reason }
    end
  end

  def category_date_reasons_for(entry, title_to_id)
    category_id = title_to_id[entry[:category]]
    return {} unless category_id

    Array(entry[:dates]).filter_map { |date_str| parsed_mention_date(category_id, date_str) }
                        .index_with { |_pair| entry[:reason] }
  end

  def parsed_mention_date(category_id, date_str)
    [category_id, Date.iso8601(date_str)]
  rescue ArgumentError
    nil
  end

  def existing_ai_category_date_pairs
    conversation.auditoria_category_mentions
                .where(category_id: active_ai_categories.ids, message_id: nil)
                .pluck(:category_id, :occurred_on)
  end

  def create_category_mentions(pairs, reason_by_pair)
    return if pairs.blank?

    now = Time.current
    rows = pairs.map do |category_id, occurred_on|
      { account_id: account.id, category_id: category_id, conversation_id: conversation.id,
        occurred_on: occurred_on, reason: reason_by_pair[[category_id, occurred_on]], created_at: now }
    end
    # rubocop:disable Rails/SkipsModelValidations
    Auditoria::CategoryMention.insert_all(rows)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def destroy_category_mentions(pairs)
    pairs.each do |category_id, occurred_on|
      conversation.auditoria_category_mentions.where(category_id: category_id, occurred_on: occurred_on, message_id: nil).delete_all
    end
  end
end

# Genera el analisis de IA de una conversacion (5 campos configurables, ver
# Auditoria::AiFieldConfig) en una sola llamada con salida estructurada
# (Auditoria::ConversationAnalyzerSchema) -- mejora sobre el sistema viejo,
# que hacia 5 llamadas separadas (una por campo).
#
# Hereda de Captain::BaseTaskService para reusar su resolucion de API key
# (cuenta propia via hook de OpenAI -> global), instrumentacion y manejo de
# errores -- la misma infraestructura que ya usa el "Summarize"/"Suggest a
# reply" nativos de Chatwoot.
class Auditoria::ConversationAnalyzerService < Captain::BaseTaskService
  include Auditoria::ConversationAnalyzerCategoryMatching

  pattr_initialize [:account!, :conversation_display_id!, { triggered_by: :manual }]

  def perform
    return skipped_result unless needs_analysis?
    return no_active_fields_error if field_configs.empty?
    return spend_limit_error unless Auditoria::AiUsageLogger.within_limit?(account)

    transcribe_pending_audio!
    return spend_limit_error unless Auditoria::AiUsageLogger.within_limit?(account)
    return no_messages_error if conversation_messages.empty?

    response = make_api_call(
      feature: 'editor', messages: messages, model: account.auditoria_chat_model.presence,
      schema: schema
    )
    return response if response[:error]

    log_usage(response)
    persist_result(response[:message])
  end

  # Nunca se adivina: si no hay analisis previo, siempre se corre. Si ya hay
  # uno, solo se vuelve a correr cuando existe al menos un mensaje (publico o
  # privado -- ver conversation_messages mas abajo) mas nuevo que la ultima
  # vez que se analizo. Mismo criterio que el sistema viejo (ai_analysis_
  # updated_at vs created_at del mensaje mas reciente).
  def needs_analysis?
    return true if analysis.blank? || analysis.analyzed_at.blank?

    latest_message_at = conversation.messages.where(message_type: [:incoming, :outgoing]).maximum(:created_at)
    latest_message_at.present? && latest_message_at > analysis.analyzed_at
  end

  def analysis
    @analysis ||= Auditoria::ConversationAnalysis.find_by(conversation_id: conversation.id)
  end

  private

  def skipped_result
    { message: analysis&.results, skipped: true }
  end

  def spend_limit_error
    { error: I18n.t('auditoria.ai_spend_limit_reached') }
  end

  def no_active_fields_error
    { error: I18n.t('auditoria.no_active_fields_to_analyze') }
  end

  def no_messages_error
    { error: I18n.t('auditoria.no_messages_to_analyze') }
  end

  # "Analizar ahora" es una accion explicita del usuario pidiendo el
  # resultado completo ya -- a diferencia del toggle "Transcribe Audio
  # Messages" (automatico, pasivo, solo corre para mensajes nuevos), aqui
  # se transcribe cualquier audio pendiente de la conversacion sin importar
  # si ese toggle esta prendido, para que el analisis nunca ignore audios
  # por falta de transcripcion. Si un audio falla, se sigue con los demas
  # -- el analisis usa lo que si haya quedado disponible (ver
  # content_for_llm), nunca aborta por un solo audio.
  def transcribe_pending_audio!
    pending_audio_messages.each do |message|
      next unless Auditoria::AiUsageLogger.within_limit?(account)

      result = Auditoria::AudioTranscriptionService.new(account: account, message: message, triggered_by: triggered_by).perform
      next unless result[:error]

      Rails.logger.error(
        "[Auditoria] audio transcription failed for message=#{message.id} account=#{account.id}: #{result[:error]}"
      )
    end
  end

  # Sin .distinct: hacer DISTINCT sobre filas que incluyen la columna jsonb
  # de attachments.meta rompe en Postgres ("could not identify an equality
  # operator for type json") -- se obtienen los ids primero (pluck, sin esa
  # columna) y se cargan los mensajes aparte. .reorder(nil) porque el
  # default_scope de Message (order by created_at) choca con SELECT DISTINCT
  # id ("ORDER BY expressions must appear in select list").
  def pending_audio_messages
    message_ids = conversation.messages
                              .reorder(nil)
                              .joins(:attachments)
                              .where(attachments: { file_type: Attachment.file_types[:audio] })
                              .where("attachments.meta ->> 'transcribed_text' IS NULL OR attachments.meta ->> 'transcribed_text' = ''")
                              .distinct
                              .pluck(:id)
    Message.where(id: message_ids)
  end

  def log_usage(response)
    cost_usd = Auditoria::AiCostCalculator.calculate(
      model: response[:model], prompt_tokens: response[:usage]['prompt_tokens'],
      completion_tokens: response[:usage]['completion_tokens']
    )
    Auditoria::AiUsageLogger.log!(
      account: account, conversation: conversation, feature: :conversation_analysis,
      model: response[:model], usage: response[:usage], cost_usd: cost_usd, triggered_by: triggered_by
    )
  end

  def persist_result(parsed_fields)
    record = analysis || Auditoria::ConversationAnalysis.new(account: account, conversation: conversation)
    record.update!(
      results: stringify_fields(parsed_fields), sentiment: parsed_fields[:sentiment],
      sentiment_reason: parsed_fields[:sentiment_reason], analyzed_at: Time.current
    )
    sync_ai_categories!(parsed_fields[:categories])
    { message: record.results }
  end

  def stringify_fields(parsed_fields)
    # :categories es un Array -- #to_s lo mangla a texto estilo inspect, asi
    # que se excluye del stringify masivo y se sincroniza aparte (ver
    # sync_ai_categories!). :sentiment/:sentiment_reason viven en su propia
    # columna (ver persist_result), no en `results`. `results` sigue siendo
    # solo field_1..field_5.
    parsed_fields.except(:categories, :sentiment, :sentiment_reason).transform_keys(&:to_s).transform_values(&:to_s)
  end

  def messages
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: conversation_text }
    ]
  end

  def system_prompt
    <<~PROMPT
      Eres un asistente experto en analisis de conversaciones de atencion al cliente por WhatsApp.

      Responde cada una de las siguientes 5 tareas, basandote unicamente en la conversacion proporcionada:

      #{field_instructions}
      #{category_instructions}

      Ademas, clasifica el sentimiento GENERAL del cliente a lo largo de toda la conversacion como positive, neutral o negative, y explica brevemente (1-2 frases) en que parte(s) de la conversacion te basas para esa clasificacion -- esto es aparte de las 5 tareas anteriores.

      Responde en #{account.locale_english_name}.
    PROMPT
  end

  def field_instructions
    field_configs.each_with_index.map do |config, index|
      instruction = "Tarea #{index + 1}: #{config.title}."
      config.subtitle.present? ? "#{instruction} #{config.subtitle}" : instruction
    end.join("\n")
  end

  def field_configs
    @field_configs ||= account.auditoria_ai_field_configs.active.limit(5)
  end

  # Inserta un marcador "Fecha: AAAA-MM-DD" cada vez que el dia cambia (no
  # por mensaje) -- le da a la IA la referencia de dia calendario que
  # necesita para reportar en que dia(s) detecto cada categoria configurada
  # (ver schema/sync_ai_categories!), sin inflar el prompt con una fecha por
  # linea.
  def conversation_text
    lines = []
    last_date = nil
    conversation_messages.each do |m|
      if m[:date] != last_date
        lines << "Fecha: #{m[:date].iso8601}"
        last_date = m[:date]
      end
      lines << "#{m[:role]}: #{m[:content]}"
    end
    lines.join("\n\n")
  end

  # Igual a Captain::BaseTaskService#conversation_messages, salvo que NO
  # excluye mensajes privados -- en Auditoria, todos los mensajes son
  # privados a proposito (ver Auditoria::MessageAnnotatorService) para que
  # jamas se reenvien por el canal real; excluirlos dejaria el contexto
  # siempre vacio.
  def conversation_messages(start_from: 0)
    collected = []
    character_count = start_from

    conversation.messages
                .where(message_type: [:incoming, :outgoing])
                .reorder('id desc')
                .each do |message|
      content = message.content_for_llm
      next if content.blank?
      break if character_count + content.length > TOKEN_LIMIT

      collected.prepend({ role: (message.incoming? ? 'user' : 'assistant'), content: content, date: message.created_at.to_date })
      character_count += content.length
    end

    collected
  end

  def event_name
    'auditoria_conversation_analysis'
  end

  def use_account_openai_hook?
    true
  end
end

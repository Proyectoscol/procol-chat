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
  pattr_initialize [:account!, :conversation_display_id!]

  def perform
    return skipped_result unless needs_analysis?

    response = make_api_call(feature: 'editor', messages: messages, schema: Auditoria::ConversationAnalyzerSchema)
    return response if response[:error]

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

  def persist_result(parsed_fields)
    record = analysis || Auditoria::ConversationAnalysis.new(account: account, conversation: conversation)
    record.update!(results: stringify_fields(parsed_fields), analyzed_at: Time.current)
    { message: record.results }
  end

  def stringify_fields(parsed_fields)
    parsed_fields.transform_keys(&:to_s).transform_values(&:to_s)
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

  def conversation_text
    conversation_messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
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

      collected.prepend({ role: (message.incoming? ? 'user' : 'assistant'), content: content })
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

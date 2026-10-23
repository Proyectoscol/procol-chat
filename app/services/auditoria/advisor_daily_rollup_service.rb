# Etapa 2 del pipeline diario de Auditor IA: sintetiza como le fue a un
# asesor en un dia especifico, agregando los Auditoria::ConversationAnalysis
# y Auditoria::CategoryMention de las conversaciones que atendio ese dia (ver
# Auditoria::AdvisorDailyRollupJob, que es quien la invoca desde el cron).
#
# Hereda de Captain::BaseTaskService como Auditoria::ConversationAnalyzerService,
# pero no opera sobre UNA conversacion -- sintetiza sobre VARIAS, asi que
# sobreescribe #conversation (usado via &. en la instrumentacion heredada)
# en vez de declarar conversation_display_id.
class Auditoria::AdvisorDailyRollupService < Captain::BaseTaskService
  pattr_initialize [:account!, :user!, :summary_date!, { triggered_by: :batch }]

  def perform
    return skipped_result if conversation_ids_for_day.empty?
    return spend_limit_error unless Auditoria::AiUsageLogger.within_limit?(account)

    response = make_api_call(messages: messages, feature: 'editor', schema: Auditoria::AdvisorDailyRollupSchema)
    return response if response[:error]

    log_usage(response)
    persist_result(response[:message])
  end

  private

  def conversation
    nil
  end

  def skipped_result
    { message: nil, skipped: true }
  end

  def spend_limit_error
    { error: I18n.t('auditoria.ai_spend_limit_reached') }
  end

  # Mismo criterio que V2::Reports::AuditoriaAdvisorSummaryBuilder: resuelve
  # el asesor via content_attributes['auditoria_source_user_id'] de cada
  # mensaje (inmutable, a diferencia de conversation.assignee_id), y excluye
  # conversaciones marcadas "auditoria-multiple-asesor" para que ningun
  # asesor se quede con metricas de una conversacion que en realidad
  # comparte con otro.
  def conversation_ids_for_day
    @conversation_ids_for_day ||= account.messages
                                         .reorder(nil) # default_scope ordena por created_at, choca con SELECT DISTINCT
                                         .where(created_at: summary_date.all_day)
                                         .where.not(conversation_id: excluded_conversation_ids)
                                         .where(
                                           "#{Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES}->>'auditoria_source_user_id' = ?",
                                           user.id.to_s
                                         )
                                         .distinct
                                         .pluck(:conversation_id)
  end

  def excluded_conversation_ids
    account.conversations.tagged_with(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE).ids
  end

  def analyses
    @analyses ||= Auditoria::ConversationAnalysis.where(conversation_id: conversation_ids_for_day)
  end

  def category_counts
    @category_counts ||= Auditoria::CategoryMention.where(conversation_id: conversation_ids_for_day, occurred_on: summary_date)
                                                   .joins(:category)
                                                   .group('auditoria_categories.title')
                                                   .count
  end

  def field_titles
    @field_titles ||= account.auditoria_ai_field_configs.active.pluck(:field_order, :title).to_h
  end

  def messages
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: analyses_text }
    ]
  end

  def system_prompt
    <<~PROMPT
      Eres un asistente experto en gestion de equipos de atencion al cliente por WhatsApp.

      A continuacion se te dan los analisis de IA de todas las conversaciones que un asesor atendio en un dia especifico, mas el conteo de categorias detectadas ese dia. Sintetiza como le fue al asesor ese dia: un resumen narrativo MUY breve de su desempeno (maximo 2-3 frases), una vision general del tono emocional predominante entre sus conversaciones, una recomendacion principal, una retroalimentacion breve y concreta en una sola frase, y una lista corta de etiquetas libres que resuman el area de retroalimentacion (ej. manejo de objeciones, conocimiento de producto).

      Responde en #{account.locale_english_name}.
    PROMPT
  end

  def analyses_text
    blocks = analyses.each_with_index.map { |analysis, index| analysis_block(analysis, index + 1) }
    (blocks + [category_counts_block]).join("\n\n")
  end

  def analysis_block(analysis, index)
    fields = analysis.results.filter_map do |key, value|
      order = key.delete_prefix('field_').to_i
      title = field_titles[order]
      "#{title}: #{value}" if title.present?
    end
    "Conversacion #{index}:\n#{fields.join("\n")}"
  end

  def category_counts_block
    return 'Categorias detectadas ese dia: ninguna.' if category_counts.empty?

    "Categorias detectadas ese dia:\n#{category_counts.map { |title, count| "- #{title}: #{count}" }.join("\n")}"
  end

  def log_usage(response)
    cost_usd = Auditoria::AiCostCalculator.calculate(
      model: response[:model], prompt_tokens: response[:usage]['prompt_tokens'],
      completion_tokens: response[:usage]['completion_tokens']
    )
    Auditoria::AiUsageLogger.log!(
      account: account, feature: :advisor_daily_rollup,
      model: response[:model], usage: response[:usage], cost_usd: cost_usd, triggered_by: triggered_by
    )
  end

  def persist_result(parsed_fields)
    record = Auditoria::AdvisorDailySummary.find_or_initialize_by(account: account, user: user, summary_date: summary_date)
    record.update!(
      conversations_count: conversation_ids_for_day.size,
      category_counts: category_counts,
      feedback_tags: Array(parsed_fields[:feedback_tags]),
      results: stringify_fields(parsed_fields),
      generated_at: Time.current
    )
    { message: record.results }
  end

  # feedback_tags es un array -- transform_values(&:to_s) lo convertiria en
  # un string ilegible ("[\"foo\", \"bar\"]"), por eso se excluye aqui y se
  # guarda aparte en su propia columna (ver persist_result).
  def stringify_fields(parsed_fields)
    parsed_fields.except(:feedback_tags).transform_keys(&:to_s).transform_values(&:to_s)
  end

  def event_name
    'auditoria_advisor_daily_rollup'
  end

  def use_account_openai_hook?
    true
  end
end

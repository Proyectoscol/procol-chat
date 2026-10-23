# Desglose de costo ANTES de disparar cualquiera de las 3 corridas manuales
# del pipeline (ver Api::V1::Accounts::Auditoria::DailyJobsController) --
# generaliza lo que antes era Auditoria::BacklogEstimateService (solo
# backlog) a los 3 kinds, un solo lugar con la logica de proyeccion de
# costo para no duplicarla 3 veces.
#
# No inventa un precio teorico por token/minuto: proyecta el PROMEDIO
# HISTORICO REAL de cost_usd que ya dejo auditoria_ai_usage_logs para esta
# cuenta (decision explicita del usuario -- el proyecto no tiene tokenizer
# real ni guarda duracion de audio, asi que un calculo teorico "$X por
# minuto" no corresponderia a como realmente cobra OpenAI).
class Auditoria::ManualRunEstimateService
  CHARS_PER_TOKEN_ESTIMATE = 4
  VALID_KINDS = %w[conversation_analysis backlog advisor_rollup].freeze

  pattr_initialize [:account!, :kind!]

  def call
    raise ArgumentError, "kind invalido: #{kind}" unless VALID_KINDS.include?(kind)

    kind == 'advisor_rollup' ? advisor_rollup_estimate : conversation_estimate
  end

  private

  def conversation_estimate
    candidate_ids = candidate_conversation_ids
    pending_audio = pending_audio_messages_count(candidate_ids)
    text_projection = cost_projection(:conversation_analysis, candidate_ids.size)
    audio_projection = cost_projection(:audio_transcription, pending_audio)

    {
      candidate_count: candidate_ids.size,
      pending_audio_messages_count: pending_audio,
      estimated_input_tokens: estimated_input_tokens(candidate_ids),
      text_analysis: text_projection,
      audio_transcription: audio_projection,
      estimated_total_cost_usd: total_cost(text_projection, audio_projection)
    }
  end

  # El rollup no tiene dimension de audio ni de tokens de entrada propios
  # (su "entrada" son los analisis ya hechos, no texto crudo) -- se dejan
  # en 0 a proposito, el frontend ya oculta esas lineas cuando son 0.
  def advisor_rollup_estimate
    text_projection = cost_projection(:advisor_daily_rollup, advisor_ids.size)

    {
      candidate_count: advisor_ids.size,
      pending_audio_messages_count: 0,
      estimated_input_tokens: 0,
      text_analysis: text_projection,
      audio_transcription: { sample_size: 0, avg_cost_usd: nil, estimated_cost_usd: nil },
      estimated_total_cost_usd: text_projection[:estimated_cost_usd]
    }
  end

  def candidate_conversation_ids
    Auditoria::DailyConversationAnalysisSchedulerJob.candidate_conversation_ids(account, unbounded: kind == 'backlog')
  end

  def advisor_ids
    @advisor_ids ||= Auditoria::AdvisorDailyRollupSchedulerJob.agent_ids_with_activity(account, Date.yesterday)
  end

  def pending_audio_messages_count(candidate_ids)
    return 0 if candidate_ids.blank?

    Attachment.where(file_type: :audio)
              .where("meta ->> 'transcribed_text' IS NULL OR meta ->> 'transcribed_text' = ''")
              .where(message_id: candidate_messages(candidate_ids).select(:id))
              .count
  end

  # Mismo tope que el analizador real (lib/captain/base_task_service.rb
  # TOKEN_LIMIT, en caracteres) por conversacion antes de sumar -- una sola
  # conversacion con historial enorme no debe inflar el estimado total mas
  # alla de lo que el prompt real le mandaria a la IA.
  def estimated_input_tokens(candidate_ids)
    return 0 if candidate_ids.blank?

    char_sums = candidate_messages(candidate_ids).group(:conversation_id).sum('LENGTH(content)')
    total_chars = char_sums.values.sum { |chars| [chars, Captain::BaseTaskService::TOKEN_LIMIT].min }
    total_chars / CHARS_PER_TOKEN_ESTIMATE
  end

  # .reorder(nil): el default_scope de Message ordena por created_at, lo que
  # choca con GROUP BY conversation_id ("column must appear in GROUP BY
  # clause") -- mismo gotcha ya resuelto antes en conversation_analyzer_
  # service.rb/advisor_daily_rollup_service.rb.
  def candidate_messages(candidate_ids)
    Message.where(conversation_id: candidate_ids, message_type: [:incoming, :outgoing]).reorder(nil)
  end

  def cost_projection(feature, unit_count)
    scope = account.auditoria_ai_usage_logs.where(feature: feature)
    sample_size = scope.count
    # .average puede devolver nil con sample_size > 0 si todos los logs de
    # esa feature tienen cost_usd nil (modelo configurado sin tabla de
    # precios en RubyLLM) -- .to_f sin &. convertiria ese nil en 0.0
    # silenciosamente, mostrando "gratis" en vez de "costo desconocido".
    avg_cost_usd = scope.average(:cost_usd)&.round(6)&.to_f

    {
      sample_size: sample_size,
      avg_cost_usd: avg_cost_usd,
      estimated_cost_usd: avg_cost_usd && (avg_cost_usd * unit_count).round(6)
    }
  end

  def total_cost(text_projection, audio_projection)
    parts = [text_projection[:estimated_cost_usd], audio_projection[:estimated_cost_usd]].compact
    parts.sum.round(6) if parts.any?
  end
end

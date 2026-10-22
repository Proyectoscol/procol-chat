# Desglose de costo ANTES de disparar un backfill completo (sin el limite
# de 3 dias del pipeline diario) -- ver Auditoria::BacklogCandidateFinder.
# No inventa un precio teorico por token/minuto: proyecta el PROMEDIO
# HISTORICO REAL de cost_usd que ya dejo auditoria_ai_usage_logs para esta
# cuenta (decision explicita del usuario, confirmada via AskUserQuestion --
# el proyecto no tiene tokenizer real ni guarda duracion de audio, asi que
# un calculo teorico "$X por minuto" no corresponderia a como realmente
# cobra OpenAI con gpt-4o-mini-transcribe, que es por tokens).
class Auditoria::BacklogEstimateService
  CHARS_PER_TOKEN_ESTIMATE = 4

  pattr_initialize [:account!]

  def call
    candidate_ids = Auditoria::BacklogCandidateFinder.conversation_ids(account)
    pending_audio = pending_audio_messages_count(candidate_ids)
    text_projection = cost_projection(:conversation_analysis, candidate_ids.size)
    audio_projection = cost_projection(:audio_transcription, pending_audio)

    {
      candidate_conversations_count: candidate_ids.size,
      pending_audio_messages_count: pending_audio,
      estimated_input_tokens: estimated_input_tokens(candidate_ids),
      text_analysis: text_projection,
      audio_transcription: audio_projection,
      estimated_total_cost_usd: total_cost(text_projection, audio_projection)
    }
  end

  private

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
    avg_cost_usd = sample_size.positive? ? scope.average(:cost_usd).to_f.round(6) : nil

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

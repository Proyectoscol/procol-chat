# Esta cuenta nunca llena reporting_events -- los mensajes del espejo
# externo son privados a proposito (ver
# Base::SendOnChannelService#invalid_message?) para que jamas se reenvien de
# verdad por el canal, y Chatwoot excluye los privados de ese pipeline (ver
# Message#valid_first_reply?/#update_waiting_since). Este builder calcula
# todo directo de messages/content_attributes en vez del pipeline nativo, y
# excluye las conversaciones marcadas "auditoria-multiple-asesor" (ver
# Auditoria::MessageAnnotatorService) para que ningun asesor se quede con
# metricas infladas o robadas por un numero que en realidad comparte con
# otro.
class V2::Reports::AuditoriaAdvisorSummaryBuilder
  pattr_initialize [:account!, :params!]

  def build
    account.account_users.map { |account_user| build_advisor_stats(account_user.user_id) }
  end

  private

  def build_advisor_stats(user_id)
    {
      id: user_id,
      conversations_count: conversation_ids_by_advisor[user_id]&.size || 0,
      avg_response_time_seconds: average_seconds(response_samples_by_advisor[user_id])
    }
  end

  def average_seconds(samples)
    return nil if samples.blank?

    (samples.sum / samples.size).round
  end

  def conversation_ids_by_advisor
    @conversation_ids_by_advisor ||= rows.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |row, acc|
      acc[row[:advisor_id]] << row[:conversation_id] if row[:advisor_id]
    end
  end

  # Recorre cada conversacion en orden y mide el tiempo entre cada mensaje
  # entrante y la siguiente respuesta saliente de un asesor resuelto -- un
  # numero honesto de "cuanto tarda en responder", promediado sobre toda la
  # historia (no solo la primera respuesta, como hace el FRT nativo).
  def response_samples_by_advisor
    return @response_samples_by_advisor if defined?(@response_samples_by_advisor)

    @response_samples_by_advisor = Hash.new { |h, k| h[k] = [] }
    rows.group_by { |row| row[:conversation_id] }.each_value { |rows_in_conversation| collect_samples(rows_in_conversation) }
    @response_samples_by_advisor
  end

  def collect_samples(rows_in_conversation)
    prev_type = nil
    prev_created_at = nil
    rows_in_conversation.each do |row|
      # prev_type puede ser nil (primer mensaje de la conversacion) -- zero?
      # explotaria con NoMethodError, == no.
      if row[:message_type] == 1 && row[:advisor_id] && prev_type == 0 # rubocop:disable Style/NumericPredicate
        @response_samples_by_advisor[row[:advisor_id]] << (row[:created_at] - prev_created_at)
      end
      prev_type = row[:message_type]
      prev_created_at = row[:created_at]
    end
  end

  def rows
    @rows ||= scoped_messages.map do |conversation_id, message_type, created_at, advisor_id|
      { conversation_id: conversation_id, message_type: message_type, created_at: created_at, advisor_id: advisor_id&.to_i }
    end
  end

  def scoped_messages
    scope = account.messages.where(created_at: range).where.not(conversation_id: excluded_conversation_ids)
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope.reorder('messages.conversation_id ASC, messages.id ASC')
         .pluck(:conversation_id, :message_type, :created_at, Arel.sql("content_attributes->>'auditoria_source_user_id'"))
  end

  def excluded_conversation_ids
    account.conversations.tagged_with(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE).ids
  end

  def inbox_id
    params[:inbox_id]
  end

  def range
    Time.zone.at(params[:since].to_i)..Time.zone.at(params[:until].to_i)
  end
end

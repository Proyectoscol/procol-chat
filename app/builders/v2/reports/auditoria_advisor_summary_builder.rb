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
    stats = agent_user_ids.map { |user_id| build_advisor_stats(user_id) }
    # Cuando se filtra por una bandeja puntual, la mayoria de asesores no
    # trabajan ahi -- mostrarlos en "--" es ruido; se quitan del todo y solo
    # quedan quienes de verdad tuvieron actividad en esa bandeja.
    stats = stats.reject { |row| row[:conversations_count].zero? } if inbox_id.present?
    { advisors: stats, totals: totals }
  end

  private

  def build_advisor_stats(user_id)
    {
      id: user_id,
      conversations_count: conversation_ids_by_advisor[user_id]&.size || 0,
      avg_response_time_seconds: average_seconds(response_samples_by_advisor[user_id])
    }
  end

  # Sobre el mismo scope ya filtrado (fecha/bandeja/multiple-asesor) que las
  # filas por asesor, para que el total/promedio general sea consistente con
  # lo que se ve en la tabla -- nunca una cifra distinta "por fuera".
  def totals
    {
      conversations_count: conversation_ids_by_advisor.values.sum(&:size),
      avg_response_time_seconds: average_seconds(response_samples_by_advisor.values.flatten)
    }
  end

  def average_seconds(samples)
    return nil if samples.blank?

    (samples.sum / samples.size).round
  end

  # Solo agentes (no administradores) -- igual que el filtro que ya aplica
  # el frontend sobre agents/getAgents, pero aqui ademas evita que un mensaje
  # resuelto por casualidad al nombre de un administrador infle el total.
  def agent_user_ids
    @agent_user_ids ||= account.account_users.where(role: :agent).pluck(:user_id)
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
      if row[:message_type] == 'outgoing' && row[:advisor_id] && prev_type == 'incoming'
        @response_samples_by_advisor[row[:advisor_id]] << (row[:created_at] - prev_created_at)
      end
      prev_type = row[:message_type]
      prev_created_at = row[:created_at]
    end
  end

  # select al final: descarta filas resueltas a un administrador, para que
  # ni las filas por asesor ni totals (ambas construidas sobre rows) se
  # inflen con un mensaje que por coincidencia calzo con el nombre de un
  # administrador.
  def rows
    return @rows if defined?(@rows)

    mapped = scoped_messages.map do |conversation_id, message_type, created_at, advisor_id|
      { conversation_id: conversation_id, message_type: message_type, created_at: created_at, advisor_id: advisor_id&.to_i }
    end
    @rows = mapped.select { |row| row[:advisor_id].nil? || agent_user_ids.include?(row[:advisor_id]) }
  end

  # pluck(:message_type) devuelve el label del enum ("incoming"/"outgoing"),
  # no el entero crudo -- Rails lo castea al leer la columna aunque sea un
  # pluck directo.
  def scoped_messages
    scope = account.messages.where(created_at: range).where.not(conversation_id: excluded_conversation_ids)
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope.reorder('messages.conversation_id ASC, messages.id ASC')
         .pluck(:conversation_id, :message_type, :created_at,
                Arel.sql("#{Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES}->>'auditoria_source_user_id'"))
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

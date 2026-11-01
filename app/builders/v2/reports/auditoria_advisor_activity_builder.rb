# Volumen y proporcion de actividad por asesor/equipo -- cuantos mensajes,
# audios, fotos, videos y llamadas (texto del espejo) maneja cada uno,
# normalizado por conversacion para poder comparar a alguien con 1
# conversacion contra alguien con 50 sin que el segundo gane solo por
# volumen. Mismo criterio de atribucion que el resto de Auditoria: una
# conversacion pertenece al unico asesor resuelto via auditoria_source_user_id
# (ver Auditoria::MessageAnnotatorService), y las marcadas multi-asesor se
# excluyen por completo (ver excluded_conversation_ids).
class V2::Reports::AuditoriaAdvisorActivityBuilder
  pattr_initialize [:account!, :params!]

  # Las 3 lineas literales que el espejo manda para eventos de llamada (ver
  # Auditoria::MessageAnnotatorService::SYSTEM_MESSAGE_LABELS) -- se buscan
  # dentro de `content` sin importar si el mensaje que las carga es
  # incoming/outgoing, porque el texto ya dice la direccion real de la
  # llamada. Derivado de esa constante (no hardcodeado aparte) para no
  # desincronizarse si cambia.
  CALL_LABELS = Auditoria::MessageAnnotatorService::SYSTEM_MESSAGE_LABELS.keys.each_with_object({}) do |label, acc|
    acc[label] = :incoming if label.include?('Incoming')
    acc[label] = :missed if label.include?('Missed')
    acc[label] = :outgoing if label.include?('Outgoing')
  end.freeze

  MEDIA_FILE_TYPES = %i[audio image video].freeze

  def build
    { advisors: agent_user_ids.map { |id| build_row(id, [id]) }, teams: account.teams.map { |team| build_team_row(team) } }
  end

  private

  def build_team_row(team)
    member_ids = TeamMember.where(team_id: team.id).pluck(:user_id) & agent_user_ids
    build_row(team.id, member_ids).merge(name: team.name)
  end

  def build_row(id, member_ids)
    rows = member_ids.flat_map { |user_id| rows_by_advisor[user_id] || [] }
    conversations_count = rows.pluck(:conversation_id).uniq.size
    outgoing_count = rows.count { |row| row[:message_type] == 'outgoing' }
    incoming_count = rows.count { |row| row[:message_type] == 'incoming' }
    {
      id: id,
      conversations_count: conversations_count,
      outgoing_count: outgoing_count,
      incoming_count: incoming_count,
      avg_outgoing_per_conversation: average(outgoing_count, conversations_count),
      avg_incoming_per_conversation: average(incoming_count, conversations_count),
      characters_written: rows.sum { |row| outgoing_text_length(row) },
      words_written: rows.sum { |row| outgoing_word_count(row) }
    }.merge(media_counts(rows)).merge(call_counts(rows))
  end

  def average(count, divisor)
    return nil if divisor.zero?

    (count.to_f / divisor).round(1)
  end

  def outgoing_text_length(row)
    return 0 unless row[:message_type] == 'outgoing'

    row[:content].to_s.length
  end

  def outgoing_word_count(row)
    return 0 unless row[:message_type] == 'outgoing'

    row[:content].to_s.split(/\s+/).count(&:present?)
  end

  def media_counts(rows)
    MEDIA_FILE_TYPES.each_with_object({}) do |file_type, acc|
      acc["#{file_type}_outgoing".to_sym] = media_count_for(rows, file_type, 'outgoing')
      acc["#{file_type}_incoming".to_sym] = media_count_for(rows, file_type, 'incoming')
    end
  end

  def media_count_for(rows, file_type, direction)
    rows.select { |row| row[:message_type] == direction }
        .sum { |row| (attachments_by_message_id[row[:id]] || []).count { |type| type == file_type.to_s } }
  end

  def call_counts(rows)
    counts = rows.filter_map { |row| call_direction_for(row) }.tally
    { calls_incoming: counts[:incoming] || 0, calls_outgoing: counts[:outgoing] || 0, calls_missed: counts[:missed] || 0 }
  end

  def call_direction_for(row)
    label = CALL_LABELS.keys.find { |candidate| row[:content].to_s.include?(candidate) }
    CALL_LABELS[label]
  end

  # Solo agentes (no administradores) -- mismo criterio que
  # AuditoriaAdvisorSummaryBuilder.
  def agent_user_ids
    @agent_user_ids ||= account.account_users.where(role: :agent).pluck(:user_id)
  end

  # conversation_id -> advisor_id: cualquier mensaje con auditoria_source_user_id
  # resuelto decide el asesor de TODA la conversacion (incoming y outgoing
  # por igual) -- mismo patron que AuditoriaSentimentScoping#advisor_user_id_by_conversation_id.
  # Las conversaciones multi-asesor ya quedan fuera de scoped_rows, asi que
  # nunca hay ambiguedad entre dos candidatos.
  def advisor_id_by_conversation_id
    @advisor_id_by_conversation_id ||= scoped_rows.each_with_object({}) do |row, acc|
      acc[row[:conversation_id]] ||= row[:advisor_id] if row[:advisor_id]
    end
  end

  # Filtra a conversaciones con un asesor resuelto que ademas sea agente
  # (no administrador) -- una conversacion resuelta a un admin por
  # coincidencia de nombre no debe inflar ninguna fila.
  def rows_by_advisor
    @rows_by_advisor ||= scoped_rows.group_by { |row| advisor_id_by_conversation_id[row[:conversation_id]] }
                                    .select { |advisor_id, _rows| advisor_id && agent_user_ids.include?(advisor_id) }
  end

  def scoped_rows
    @scoped_rows ||= scoped_messages.map do |id, conversation_id, message_type, content, advisor_id|
      { id: id, conversation_id: conversation_id, message_type: message_type, content: content, advisor_id: advisor_id&.to_i }
    end
  end

  def scoped_messages
    scope = account.messages.where(created_at: range, message_type: [:incoming, :outgoing])
                   .where.not(conversation_id: excluded_conversation_ids)
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope.pluck(:id, :conversation_id, :message_type, :content,
                Arel.sql("#{Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES}->>'auditoria_source_user_id'"))
  end

  def scoped_message_ids
    @scoped_message_ids ||= scoped_rows.pluck(:id)
  end

  def attachments_by_message_id
    @attachments_by_message_id ||= Attachment
                                   .where(account_id: account.id, message_id: scoped_message_ids, file_type: MEDIA_FILE_TYPES)
                                   .pluck(:message_id, :file_type)
                                   .group_by { |message_id, _file_type| message_id }
                                   .transform_values { |pairs| pairs.map { |_message_id, file_type| file_type } }
  end

  def excluded_conversation_ids
    Auditoria::MessageAnnotatorService.multi_advisor_excluded_conversation_ids(account)
  end

  def inbox_id
    params[:inbox_id]
  end

  def range
    Time.zone.at(params[:since].to_i)..Time.zone.at(params[:until].to_i)
  end
end

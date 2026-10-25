# Tiempo de respuesta promedio (brecha entrante->saliente) agrupado por
# equipo o por inbox, para los reportes NATIVOS de Chatwoot (Team/Inbox
# Overview) en cuentas de Auditoria -- estas cuentas reciben los mensajes
# por un espejo externo marcado privado a proposito (ver
# Base::SendOnChannelService#invalid_message?), asi que reporting_events
# NUNCA se llena y el avg_first_response_time nativo (Reports::DataSource)
# siempre sale nil. Mismo calculo honesto que ya usa
# V2::Reports::AuditoriaAdvisorSummaryBuilder (brecha real entre cada
# mensaje entrante y la siguiente respuesta saliente), pero agrupado por
# conversations.team_id/messages.inbox_id en vez de por asesor -- aqui no
# hace falta excluir conversaciones con mas de un asesor (esa exclusion
# existe solo para no atribuirle a un asesor una respuesta ajena; un
# promedio por equipo/inbox no le pertenece a nadie en particular).
class Auditoria::ResponseTimeCalculator
  pattr_initialize [:account!, :range!]

  GROUP_COLUMNS = { team_id: 'conversations.team_id', inbox_id: 'messages.inbox_id' }.freeze

  # group_by: :team_id o :inbox_id -- {group_value => avg_seconds (o nil
  # si ese grupo no tuvo ninguna brecha entrante->saliente en el rango)}.
  def average_seconds_by(group_by)
    samples_by_group(group_by).transform_values { |seconds_list| average(seconds_list) }
  end

  # Promedio general de toda la cuenta (sin agrupar) -- para el resumen de
  # Conversations Overview, que no tiene un dimension_id especifico.
  def average_seconds
    average(rows.group_by { |row| row[:conversation_id] }.values.flat_map { |rows_in_conversation| response_gaps(rows_in_conversation) })
  end

  private

  def average(seconds_list)
    return nil if seconds_list.blank?

    (seconds_list.sum / seconds_list.size).round
  end

  def samples_by_group(group_by)
    grouped = Hash.new { |h, k| h[k] = [] }
    rows.group_by { |row| row[:conversation_id] }.each_value do |rows_in_conversation|
      group_value = rows_in_conversation.first[group_by]
      next if group_value.nil?

      response_gaps(rows_in_conversation).each { |seconds| grouped[group_value] << seconds }
    end
    grouped
  end

  def response_gaps(rows_in_conversation)
    gaps = []
    prev_type = nil
    prev_created_at = nil
    rows_in_conversation.each do |row|
      gaps << (row[:created_at] - prev_created_at) if row[:message_type] == 'outgoing' && prev_type == 'incoming'
      prev_type = row[:message_type]
      prev_created_at = row[:created_at]
    end
    gaps
  end

  # message_type: [:incoming, :outgoing] explicito -- sin esto, cualquier otro
  # tipo intercalado (activity, template, etc) rompe la adyacencia
  # entrante->saliente que detecta response_gaps (prev_type dejaria de ser
  # 'incoming' justo antes de la respuesta real).
  def rows
    @rows ||= account.messages
                     .joins(:conversation)
                     .where(created_at: range, message_type: [:incoming, :outgoing])
                     .reorder('messages.conversation_id ASC, messages.id ASC')
                     .pluck(:conversation_id, :message_type, :created_at, :inbox_id, 'conversations.team_id')
                     .map { |values| row_hash(*values) }
  end

  def row_hash(conversation_id, message_type, created_at, inbox_id, team_id)
    { conversation_id: conversation_id, message_type: message_type, created_at: created_at, inbox_id: inbox_id, team_id: team_id }
  end
end

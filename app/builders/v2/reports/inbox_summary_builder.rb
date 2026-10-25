class V2::Reports::InboxSummaryBuilder < V2::Reports::BaseSummaryBuilder
  pattr_initialize [:account!, :params!]

  def build
    load_data
    prepare_report
  end

  private

  attr_reader :conversations_count, :resolved_count,
              :avg_resolution_time, :avg_first_response_time, :avg_reply_time

  def prepare_report
    account.inboxes.map do |inbox|
      build_inbox_stats(inbox)
    end
  end

  def build_inbox_stats(inbox)
    {
      id: inbox.id,
      conversations_count: conversations_count[inbox.id] || 0,
      resolved_conversations_count: resolved_count[inbox.id] || 0,
      avg_resolution_time: avg_resolution_time[inbox.id],
      avg_first_response_time: avg_first_response_time[inbox.id] || auditoria_avg_response_time[inbox.id],
      avg_reply_time: avg_reply_time[inbox.id]
    }
  end

  def group_by_key
    :inbox_id
  end

  # Ver el mismo fallback en V2::Reports::TeamSummaryBuilder: reporting_events
  # nunca se llena en cuentas de Auditoria (mensajes privados a proposito por
  # el espejo externo), asi que avg_first_response_time nativo siempre sale
  # nil aqui.
  def auditoria_avg_response_time
    @auditoria_avg_response_time ||= if account.feature_enabled?('auditoria') && range.present?
                                       Auditoria::ResponseTimeCalculator.new(account: account, range: range).average_seconds_by(:inbox_id)
                                     else
                                       {}
                                     end
  end
end

class V2::Reports::TeamSummaryBuilder < V2::Reports::BaseSummaryBuilder
  pattr_initialize [:account!, :params!]

  private

  attr_reader :conversations_count, :resolved_count,
              :avg_resolution_time, :avg_first_response_time, :avg_reply_time

  def prepare_report
    account.teams.map do |team|
      build_team_stats(team)
    end
  end

  def build_team_stats(team)
    {
      id: team.id,
      conversations_count: conversations_count[team.id] || 0,
      resolved_conversations_count: resolved_count[team.id] || 0,
      avg_resolution_time: avg_resolution_time[team.id],
      avg_first_response_time: avg_first_response_time[team.id] || auditoria_avg_response_time[team.id],
      avg_reply_time: avg_reply_time[team.id]
    }
  end

  def group_by_key
    'conversations.team_id'
  end

  # El pipeline nativo (reporting_events) nunca se llena en cuentas de
  # Auditoria -- los mensajes llegan por un espejo externo marcado privado
  # a proposito (ver Base::SendOnChannelService#invalid_message?), y
  # Chatwoot excluye los privados de ese pipeline. Sin este fallback,
  # avg_first_response_time queda nil siempre para estas cuentas, aunque
  # si tengamos la info (ver Auditoria::ResponseTimeCalculator, mismo
  # calculo que ya usa el reporte de Asesores).
  def auditoria_avg_response_time
    @auditoria_avg_response_time ||= if account.feature_enabled?('auditoria') && range.present?
                                       Auditoria::ResponseTimeCalculator.new(account: account, range: range).average_seconds_by(:team_id)
                                     else
                                       {}
                                     end
  end
end

class V2::Reports::Conversations::MetricBuilder < V2::Reports::Conversations::BaseReportBuilder
  def summary
    {
      conversations_count: count('conversations_count'),
      incoming_messages_count: count('incoming_messages_count'),
      outgoing_messages_count: count('outgoing_messages_count'),
      avg_first_response_time: count('avg_first_response_time') || auditoria_avg_response_time,
      avg_resolution_time: count('avg_resolution_time'),
      resolutions_count: count('resolutions_count'),
      reply_time: count('reply_time')
    }
  end

  def bot_summary
    {
      bot_resolutions_count: count('bot_resolutions_count'),
      bot_handoffs_count: count('bot_handoffs_count')
    }
  end

  private

  def count(metric)
    builder_class(metric).new(account, builder_params(metric)).aggregate_value
  end

  def builder_params(metric)
    params.merge({ metric: metric })
  end

  # Mismo fallback que V2::Reports::TeamSummaryBuilder/InboxSummaryBuilder:
  # reporting_events nunca se llena en cuentas de Auditoria, asi que
  # avg_first_response_time nativo sale nil aqui tambien. Este builder se
  # reusa tanto para el resumen general de cuenta (Conversations Overview,
  # sin type/id) como para el detalle por equipo/bandeja (WootReports.vue,
  # con type+id) -- hay que respetar esa misma dimension, nunca devolver un
  # promedio de cuenta completa cuando se pidio uno de un equipo/bandeja
  # puntual.
  def auditoria_avg_response_time
    return unless account.feature_enabled?('auditoria') && range.present?

    calculator = Auditoria::ResponseTimeCalculator.new(account: account, range: range)
    case params[:type]&.to_sym
    when :account, nil
      calculator.average_seconds
    when :team
      calculator.average_seconds_by(:team_id)[params[:id].to_i]
    when :inbox
      calculator.average_seconds_by(:inbox_id)[params[:id].to_i]
    end
  end

  def range
    return unless params[:since].present? && params[:until].present?

    Time.zone.at(params[:since].to_i)..Time.zone.at(params[:until].to_i)
  end
end

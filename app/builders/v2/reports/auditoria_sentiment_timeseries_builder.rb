# Tendencia de sentimiento de IA (por conversacion completa) agregada por
# dia/semana/mes, filtrable por asesor, equipo, o bandeja -- responde "esta
# mejorando o empeorando este asesor/equipo" con evidencia de conversacion,
# no solo el agregado diario (ver Auditoria::AdvisorDailySummary). A
# diferencia de las menciones de categoria (un conteo por mensaje que
# matchea), aqui una conversacion cuenta UNA sola vez, en el dia que
# empezo (conversations.created_at) -- el sentimiento es un veredicto sobre
# el CASO completo, no algo que se reparta entre dias.
class V2::Reports::AuditoriaSentimentTimeseriesBuilder
  include V2::Reports::Concerns::AuditoriaTimeBucketing

  pattr_initialize [:account!, :params!]

  SENTIMENTS = %w[positive neutral negative].freeze

  def build
    { bucket: bucket_resolution.to_s, series: series_by_sentiment }
  end

  private

  def series_by_sentiment
    SENTIMENTS.map { |sentiment| { sentiment: sentiment, points: points_by_sentiment[sentiment] || [] } }
  end

  def points_by_sentiment
    @points_by_sentiment ||= grouped_points.transform_values { |points| points.sort_by { |p| p[:date] } }
  end

  def grouped_points
    scoped_analyses.group(:sentiment, bucket_column).count.each_with_object(Hash.new { |h, k| h[k] = [] }) do |pair, acc|
      (sentiment, bucket_value), count = pair
      acc[sentiment] << { date: bucket_start_date(bucket_value).iso8601, count: count }
    end
  end

  # bucket_resolution nunca viene de params/usuario -- se calcula solo a
  # partir del rango de fechas (ver el concern AuditoriaTimeBucketing), asi
  # que interpolar su valor aqui no es una via de SQL injection. Time.zone.name
  # tampoco (viene de config.time_zone, no del cliente).
  #
  # conversations.created_at es `timestamp without time zone` guardado en
  # UTC (ActiveRecord.default_timezone = :utc) -- date_trunc('day', ...)
  # directo trunca con el valor UTC crudo, no con el dia calendario real en
  # la zona de la cuenta (America/Bogota, GMT-5). Una conversacion creada
  # despues de las 7pm hora Bogota cae en la madrugada UTC del dia
  # siguiente, asi que sin este AT TIME ZONE queda contada un dia adelante
  # (mismo tipo de bug que el de graficas en el commit 30abe4d1b, pero en
  # SQL en vez de JS). occurred_on en el reporte de Categorias no lo sufre
  # porque ya es un Date calculado en Ruby con Time.zone (ver
  # Auditoria::KeywordCategoryMatcherService), no un timestamp truncado en
  # SQL.
  def bucket_column
    Arel.sql("date_trunc('#{bucket_resolution}', conversations.created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{Time.zone.tzinfo.name}')")
  end

  def scoped_analyses
    Auditoria::ConversationAnalysis
      .where(account_id: account.id, sentiment: SENTIMENTS, conversation_id: filtered_conversation_ids)
      .joins(:conversation)
  end

  def filtered_conversation_ids
    @filtered_conversation_ids ||= begin
      ids = base_conversation_ids
      ids &= advisor_scoped_conversation_ids if advisor_scoped?
      ids
    end
  end

  # Punto de partida: conversaciones con sentimiento ya clasificado, en el
  # rango de fechas, excluyendo las marcadas con mas de un asesor (mismo
  # criterio que Auditoria::AdvisorDailyRollupService) -- una conversacion
  # con mas de un asesor no se le puede atribuir a nadie en particular.
  def base_conversation_ids
    @base_conversation_ids ||= begin
      scope = Auditoria::ConversationAnalysis
              .where(account_id: account.id, sentiment: SENTIMENTS)
              .joins(:conversation)
              .where(conversations: { created_at: timestamp_range })
              .where.not(conversation_id: excluded_conversation_ids)
      scope = scope.where(conversations: { inbox_id: inbox_id }) if inbox_id.present?
      scope.pluck(:conversation_id)
    end
  end

  def timestamp_range
    Time.zone.at(params[:since].to_i)..Time.zone.at(params[:until].to_i)
  end

  def excluded_conversation_ids
    account.conversations.tagged_with(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE).ids
  end

  def advisor_scoped?
    user_id.present? || team_id.present?
  end

  def advisor_scoped_conversation_ids
    advisor_user_id_by_conversation_id.select { |_conversation_id, advisor_id| target_user_ids.include?(advisor_id) }.keys
  end

  def target_user_ids
    @target_user_ids ||= user_id.present? ? [user_id.to_i] : TeamMember.where(team_id: team_id).pluck(:user_id)
  end

  # Para una conversacion SIN el label de multi-asesor (ya excluidas en
  # base_conversation_ids), cualquier mensaje con auditoria_source_user_id
  # da el asesor de todo el caso -- son todos iguales por definicion (ver
  # Auditoria::MessageAnnotatorService#flag_multiple_advisors).
  def advisor_user_id_by_conversation_id
    source_column = Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES
    @advisor_user_id_by_conversation_id ||= account.messages
                                                   .where(conversation_id: base_conversation_ids)
                                                   .where("#{source_column}->>'auditoria_source_user_id' IS NOT NULL")
                                                   .pluck(:conversation_id, Arel.sql("#{source_column}->>'auditoria_source_user_id'"))
                                                   .to_h.transform_values(&:to_i)
  end

  def user_id
    params[:user_id]
  end

  def team_id
    params[:team_id]
  end

  def inbox_id
    params[:inbox_id]
  end
end

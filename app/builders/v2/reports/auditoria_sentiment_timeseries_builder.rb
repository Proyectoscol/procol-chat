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
  include V2::Reports::Concerns::AuditoriaSentimentScoping

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

  # La tendencia siempre trae los 3 sentimientos (las 3 lineas fijas de la
  # grafica) -- a diferencia del drilldown de conversaciones, que puede
  # acotar a uno solo (ver AuditoriaSentimentConversationsBuilder#sentiment_filter).
  def sentiment_filter
    SENTIMENTS
  end
end

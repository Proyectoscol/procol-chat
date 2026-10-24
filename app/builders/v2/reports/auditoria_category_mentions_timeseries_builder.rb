# Menciones (o conversaciones) por dia/semana/mes, para la grafica de linea
# de tiempo del panel de categorias. A diferencia del resumen, SI es
# sensible a fecha -- occurred_on ya viene resuelto (mensaje real para
# palabra clave, dia reportado por el LLM para IA), asi que un GROUP BY
# funciona igual para ambos mecanismos sin caso especial.
class V2::Reports::AuditoriaCategoryMentionsTimeseriesBuilder
  include V2::Reports::Concerns::AuditoriaTimeBucketing

  pattr_initialize [:account!, :params!]

  def build
    { bucket: bucket_resolution.to_s, series: series_by_category }
  end

  private

  def series_by_category
    categories.map do |category|
      { id: category.id, title: category.title, points: points_by_category_id[category.id] || [] }
    end
  end

  def points_by_category_id
    @points_by_category_id ||= grouped_points.transform_values { |points| points.sort_by { |p| p[:date] } }
  end

  # Mismo criterio que AuditoriaCategorySummaryBuilder: en modo "menciones"
  # cada fila de auditoria_category_mentions cuenta (crudo); en modo
  # "conversaciones" se deduplica por conversation_id dentro de cada bucket,
  # para no doblar un bucket donde la misma conversacion matcheo mas de una vez.
  def grouped_points
    grouped = if mentions_mode?
                scoped_mentions.group(:category_id, bucket_column).count
              else
                scoped_mentions.group(:category_id, bucket_column).distinct.count(:conversation_id)
              end
    grouped.each_with_object(Hash.new { |h, k| h[k] = [] }) do |pair, acc|
      (category_id, bucket_value), count = pair
      acc[category_id] << { date: bucket_start_date(bucket_value).iso8601, count: count }
    end
  end

  def bucket_column
    return :occurred_on if bucket_resolution == :day

    # bucket_resolution nunca viene de params/usuario -- se calcula solo a
    # partir del rango de fechas (ver el concern AuditoriaTimeBucketing), asi
    # que interpolar su valor aqui no es una via de SQL injection.
    Arel.sql("date_trunc('#{bucket_resolution}', occurred_on)")
  end

  def mentions_mode?
    params[:count_mode] == 'mentions'
  end

  def categories
    @categories ||= begin
      scope = category_ids.present? ? account.auditoria_categories.where(id: category_ids) : account.auditoria_categories
      scope.to_a.select { |category| category_visible?(category) }
    end
  end

  # Mismo criterio que AuditoriaCategorySummaryBuilder: inbox_id llega forzado
  # a los inboxes permitidos para un admin restringido.
  def category_visible?(category)
    return true if inbox_id.blank?

    Array(inbox_id).map(&:to_i).any? { |id| category.applies_to_inbox?(id) }
  end

  def scoped_mentions
    scope = Auditoria::CategoryMention.where(account_id: account.id, category_id: categories.map(&:id), occurred_on: range)
    scope = scope.joins(:conversation).where(conversations: { inbox_id: inbox_id }) if inbox_id.present?
    scope
  end

  def category_ids
    Array(params[:category_ids]).map(&:to_i).presence
  end

  def inbox_id
    params[:inbox_id]
  end
end

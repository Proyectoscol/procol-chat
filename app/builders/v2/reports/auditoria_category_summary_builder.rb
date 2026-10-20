# A diferencia de AuditoriaAdvisorSummaryBuilder, este reporte NO acepta
# since/until -- es el resumen "cuantas conversaciones tienen esta categoria
# ahora mismo", util para el drilldown. La serie de tiempo (sensible a
# fecha) vive en AuditoriaCategoryMentionsTimeseriesBuilder.
#
# Lista TODAS las categorias configuradas (activas e inactivas) -- is_active
# solo pausa el matching de contenido nuevo, no borra coincidencias
# historicas; el gerente sigue viendo el conteo acumulado aunque alguien haya
# desactivado la categoria.
class V2::Reports::AuditoriaCategorySummaryBuilder
  pattr_initialize [:account!, :params!]

  def build
    { categories: categories_with_counts, totals: { conversations_count: distinct_conversations_count } }
  end

  private

  def categories_with_counts
    account.auditoria_categories.order(:title).map do |category|
      { id: category.id, title: category.title, conversations_count: counts_by_category_id[category.id] || 0 }
    end
  end

  # group(:category_id).distinct.count(:conversation_id) ya es un conteo de
  # conversaciones DISTINTAS por categoria -- puede haber varias filas de
  # mencion (una por mensaje, o una por dia de IA) para la misma conversacion
  # y categoria.
  def counts_by_category_id
    @counts_by_category_id ||= scoped_mentions.group(:category_id).distinct.count(:conversation_id)
  end

  def distinct_conversations_count
    scoped_mentions.distinct.count(:conversation_id)
  end

  def scoped_mentions
    scope = Auditoria::CategoryMention.where(account_id: account.id)
    scope = scope.joins(:conversation).where(conversations: { inbox_id: inbox_id }) if inbox_id.present?
    scope
  end

  def inbox_id
    params[:inbox_id]
  end
end

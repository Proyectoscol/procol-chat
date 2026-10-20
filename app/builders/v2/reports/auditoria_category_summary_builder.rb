# A diferencia de AuditoriaAdvisorSummaryBuilder, este reporte NO acepta
# since/until -- es el resumen "cuantas conversaciones/menciones tiene esta
# categoria ahora mismo", util para el drilldown. La serie de tiempo
# (sensible a fecha) vive en AuditoriaCategoryMentionsTimeseriesBuilder.
#
# Lista TODAS las categorias configuradas (activas e inactivas, padres e
# hijas) -- is_active solo pausa el matching de contenido nuevo, no borra
# coincidencias historicas; el gerente sigue viendo el conteo acumulado
# aunque alguien haya desactivado la categoria.
class V2::Reports::AuditoriaCategorySummaryBuilder
  pattr_initialize [:account!, :params!]

  def build
    { categories: categories_with_counts, totals: { conversations_count: total_count } }
  end

  private

  def categories_with_counts
    all_categories.map do |category|
      has_subcategories = parent_ids.include?(category.id)
      {
        id: category.id, title: category.title, parent_id: category.parent_id,
        has_subcategories: has_subcategories,
        conversations_count: count_for(category, has_subcategories)
      }
    end
  end

  # Una categoria padre (ej. "Competencia") nunca matchea por si misma
  # (ver Auditoria::Category.leaf) -- su conteo es el acumulado ("rollup")
  # de sus subcategorias.
  def count_for(category, has_subcategories)
    return counts_by_category_id[category.id] || 0 unless has_subcategories

    rollup_ids = [category.id] + children_by_parent_id[category.id].map(&:id)
    return rollup_ids.sum { |id| counts_by_category_id[id] || 0 } if mentions_mode?

    # Modo "conversaciones" (no menciones): sumar los conteos DISTINTOS de
    # cada subcategoria sobre-contaria una conversacion que menciona mas de
    # una subcategoria (ej. "Kia" y "Toyota" en el mismo mensaje) -- se
    # recalcula con un solo DISTINCT sobre la union de ids para no doblar.
    scoped_mentions.where(category_id: rollup_ids).distinct.count(:conversation_id)
  end

  def all_categories
    @all_categories ||= account.auditoria_categories.order(:title).to_a
  end

  def parent_ids
    @parent_ids ||= all_categories.filter_map(&:parent_id).to_set
  end

  def children_by_parent_id
    @children_by_parent_id ||= all_categories.group_by(&:parent_id)
  end

  # group(:category_id).distinct.count(:conversation_id) ya es un conteo de
  # conversaciones DISTINTAS por categoria -- puede haber varias filas de
  # mencion (una por mensaje, o una por dia de IA) para la misma conversacion
  # y categoria. En modo "menciones" es un conteo crudo de filas (cada fila
  # = una mencion real, sin deduplicar).
  def counts_by_category_id
    @counts_by_category_id ||= if mentions_mode?
                                 scoped_mentions.group(:category_id).count
                               else
                                 scoped_mentions.group(:category_id).distinct.count(:conversation_id)
                               end
  end

  def total_count
    mentions_mode? ? scoped_mentions.count : scoped_mentions.distinct.count(:conversation_id)
  end

  def mentions_mode?
    params[:count_mode] == 'mentions'
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

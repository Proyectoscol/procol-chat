# Un solo metodo para dos casos de uso, nunca se duplica el SQL de matching:
#   - Tiempo real (Auditoria::KeywordCategoryMatcherJob): messages = los
#     mensajes NUEVOS de una conversacion, categories = todas las categorias
#     keyword de la cuenta.
#   - Backfill (Auditoria::KeywordCategoryBackfillJob): messages = TODOS los
#     mensajes historicos de la cuenta, categories = la UNA categoria recien
#     creada/editada.
# occurred_on viene del created_at real de cada mensaje (zona Bogota, ver
# nota de timezone en auditoria_advisor_summary_builder.rb) -- el backfill
# conserva fechas historicas reales, nunca "hoy".
class Auditoria::KeywordCategoryMatcherService
  pattr_initialize [:messages!, :categories!]

  def call
    # find_each no aplica -- maximo 10 categorias por cuenta
    # (Auditoria::Category::MAX_CATEGORIES_PER_ACCOUNT), no una tabla grande.
    # rubocop:disable Rails/FindEach
    categories.active.where(match_type: :keyword).each { |category| match_category(category) }
    # rubocop:enable Rails/FindEach
  end

  private

  def match_category(category)
    patterns = category.search_terms_list.map { |term| "\\y#{Regexp.escape(term)}\\y" }
    return if patterns.blank?

    rows = messages.where(message_type: [:incoming, :outgoing])
                   .where('content ~* ANY(ARRAY[?])', patterns)
                   .pluck(:id, :account_id, :conversation_id, :created_at)
                   .map do |message_id, account_id, conversation_id, created_at|
      {
        message_id: message_id, account_id: account_id, conversation_id: conversation_id,
        category_id: category.id, occurred_on: created_at.to_date, created_at: Time.current
      }
    end
    return if rows.blank?

    # insert_all respeta el indice unique parcial [message_id, category_id]
    # -- re-correr el backfill o reintentar el job nunca duplica filas.
    # rubocop:disable Rails/SkipsModelValidations
    Auditoria::CategoryMention.insert_all(rows)
    # rubocop:enable Rails/SkipsModelValidations
  end
end

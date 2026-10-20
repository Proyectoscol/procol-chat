# Desglose de una categoria de palabra clave por termino de busqueda
# individual, para el click-to-detail "terminos" del reporte -- cuantas de
# las menciones ya registradas disparo cada termino configurado. Las
# categorias padre y las de tipo :ai no tienen terminos propios (ver
# Auditoria::Category.leaf y Auditoria::KeywordCategoryMatcherService), asi
# que devuelven una lista vacia en vez de reventar.
class V2::Reports::AuditoriaCategoryTermsBuilder
  pattr_initialize [:account!, :params!]

  def build
    { terms: terms_with_counts }
  end

  private

  def terms_with_counts
    return [] unless category&.match_type_keyword?

    rows = category.search_terms_list.map do |term|
      { term: term, mentions_count: matched_messages.where('content ~* ?', pattern_for(term)).count }
    end
    rows.sort_by { |row| -row[:mentions_count] }
  end

  def pattern_for(term)
    "\\y#{Regexp.escape(term)}\\y"
  end

  # Mismas filas que ya cuentan como mencion de esta categoria (ver
  # AuditoriaCategorySummaryBuilder) -- aqui solo se re-evalua CUAL termino
  # matcheo cada mensaje ya confirmado, no se re-decide si matchea o no.
  def matched_messages
    @matched_messages ||= Message.where(id: matched_message_ids)
  end

  def matched_message_ids
    scoped_mentions.where.not(message_id: nil).pluck(:message_id)
  end

  def scoped_mentions
    scope = Auditoria::CategoryMention.where(account_id: account.id, category_id: category.id)
    scope = scope.where(occurred_on: range) if range
    scope = scope.joins(:conversation).where(conversations: { inbox_id: inbox_id }) if inbox_id.present?
    scope
  end

  def range
    return unless params[:since].present? && params[:until].present?

    Time.zone.at(params[:since].to_i).to_date..Time.zone.at(params[:until].to_i).to_date
  end

  def category
    @category ||= account.auditoria_categories.find_by(id: params[:category_id])
  end

  def inbox_id
    params[:inbox_id]
  end
end

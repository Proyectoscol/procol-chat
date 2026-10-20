# Se encola al crear o editar una categoria :keyword para que las
# coincidencias retroactivas aparezcan de inmediato, con sus fechas reales,
# sin esperar mensajes nuevos. Limpia primero TODAS las filas de esta
# categoria (sin importar que mecanismo las creo) porque el match_type es
# una sola fuente de verdad; si el tipo actual sigue siendo :keyword, las
# repuebla ya mismo. Si cambio a :ai, se detiene ahi -- repoblar IA de forma
# masiva implicaria miles de llamadas de pago, eso solo pasa conversacion
# por conversacion en su proximo analisis.
class Auditoria::KeywordCategoryBackfillJob < ApplicationJob
  queue_as :low

  def perform(category_id)
    category = Auditoria::Category.find_by(id: category_id)
    return unless category

    Auditoria::CategoryMention.where(category_id: category.id).delete_all

    Auditoria::KeywordCategoryMatcherService.new(
      messages: category.account.messages,
      categories: Auditoria::Category.where(id: category.id)
    ).call
  end
end

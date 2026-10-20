class Api::V1::Accounts::Auditoria::CategoriesController < Api::V1::Accounts::BaseController
  # Sin esto, ActionController::ParamsWrapper resuelve el modelo envuelto
  # bajo :category hacia el ::Category NATIVO de Chatwoot (categorias del
  # Centro de Ayuda) en vez de Auditoria::Category -- confirmado: existe
  # app/models/category.rb y la resolucion por defecto de namespaces recorta
  # el prefijo Api::V1::Accounts::Auditoria:: hasta dar con esa clase nativa.
  # Sus columnas (name, slug, icon...) no calzan con las nuestras, el hash
  # envuelto quedaria vacio, y create/update explotarian con ParameterMissing
  # siempre. wrap_parameters explicito evita la adivinanza.
  wrap_parameters :category, include: %i[title match_type is_active search_terms instructions parent_id]

  before_action :check_authorization
  before_action :fetch_category, only: [:update, :destroy]

  def index
    render json: Current.account.auditoria_categories.order(:title).map { |category| serialize(category) }
  end

  def create
    category = Current.account.auditoria_categories.create!(category_params)
    reconcile_new_parent_mentions(category)
    Auditoria::KeywordCategoryBackfillJob.perform_later(category.id)
    render json: serialize(category)
  end

  def update
    @category.assign_attributes(category_params)
    needs_reconcile = @category.match_type_changed? || @category.search_terms_changed?
    @category.save!
    reconcile_new_parent_mentions(@category)
    Auditoria::KeywordCategoryBackfillJob.perform_later(@category.id) if needs_reconcile
    render json: serialize(@category)
  end

  def destroy
    @category.destroy!
    head :no_content
  end

  private

  def fetch_category
    @category = Current.account.auditoria_categories.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:title, :match_type, :is_active, :search_terms, :instructions, :parent_id)
  end

  # Si esta categoria acaba de convertirse en padre (gano su primera
  # subcategoria), sus propias menciones viejas (de cuando era una hoja
  # independiente) quedan obsoletas -- de lo contrario su conteo en el
  # reporte sumaria historial propio ya irrelevante junto con el de sus
  # subcategorias. El chequeo count == 1 hace esto idempotente: solo limpia
  # en la transicion exacta, nunca en saves posteriores con el padre ya
  # establecido.
  def reconcile_new_parent_mentions(category)
    return if category.parent.blank?
    return unless category.parent.subcategories.count == 1

    Auditoria::CategoryMention.where(category_id: category.parent_id).delete_all
  end

  def serialize(category)
    {
      id: category.id, title: category.title, match_type: category.match_type,
      is_active: category.is_active, search_terms: category.search_terms, instructions: category.instructions,
      parent_id: category.parent_id, has_subcategories: category.subcategories?
    }
  end

  def check_authorization
    authorize(:'auditoria/categories')
  end
end

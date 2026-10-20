class Api::V1::Accounts::Auditoria::CategoriesController < Api::V1::Accounts::BaseController
  # Sin esto, ActionController::ParamsWrapper resuelve el modelo envuelto
  # bajo :category hacia el ::Category NATIVO de Chatwoot (categorias del
  # Centro de Ayuda) en vez de Auditoria::Category -- confirmado: existe
  # app/models/category.rb y la resolucion por defecto de namespaces recorta
  # el prefijo Api::V1::Accounts::Auditoria:: hasta dar con esa clase nativa.
  # Sus columnas (name, slug, icon...) no calzan con las nuestras, el hash
  # envuelto quedaria vacio, y create/update explotarian con ParameterMissing
  # siempre. wrap_parameters explicito evita la adivinanza.
  wrap_parameters :category, include: %i[title match_type is_active search_terms instructions]

  before_action :check_authorization
  before_action :fetch_category, only: [:update, :destroy]

  def index
    render json: Current.account.auditoria_categories.order(:title).map { |category| serialize(category) }
  end

  def create
    category = Current.account.auditoria_categories.create!(category_params)
    Auditoria::KeywordCategoryBackfillJob.perform_later(category.id)
    render json: serialize(category)
  end

  def update
    @category.assign_attributes(category_params)
    needs_reconcile = @category.match_type_changed? || @category.search_terms_changed?
    @category.save!
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
    params.require(:category).permit(:title, :match_type, :is_active, :search_terms, :instructions)
  end

  def serialize(category)
    {
      id: category.id, title: category.title, match_type: category.match_type,
      is_active: category.is_active, search_terms: category.search_terms, instructions: category.instructions
    }
  end

  def check_authorization
    authorize(:'auditoria/categories')
  end
end

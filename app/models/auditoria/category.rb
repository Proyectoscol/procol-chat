# == Schema Information
#
# Table name: auditoria_categories
#
#  id           :bigint           not null, primary key
#  inbox_ids    :integer          default([]), not null, is an Array
#  instructions :text
#  is_active    :boolean          default(TRUE), not null
#  match_type   :integer          default("keyword"), not null
#  search_terms :text
#  title        :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  parent_id    :bigint
#
# Indexes
#
#  index_auditoria_categories_on_account_and_title  (account_id,title) UNIQUE
#  index_auditoria_categories_on_account_id         (account_id)
#  index_auditoria_categories_on_inbox_ids          (inbox_ids) USING gin
#  index_auditoria_categories_on_parent_id          (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (parent_id => auditoria_categories.id) ON DELETE => nullify
#
class Auditoria::Category < ApplicationRecord
  self.table_name = 'auditoria_categories'

  MAX_CATEGORIES_PER_ACCOUNT = 10

  belongs_to :account
  belongs_to :parent, class_name: 'Auditoria::Category', optional: true
  has_many :subcategories, class_name: 'Auditoria::Category', foreign_key: :parent_id, inverse_of: :parent,
                           dependent: :nullify
  has_many :auditoria_category_mentions, class_name: 'Auditoria::CategoryMention', dependent: :destroy

  enum :match_type, { keyword: 0, ai: 1 }, prefix: true

  validates :title, presence: true, uniqueness: { scope: :account_id }
  validate :max_categories_per_account, on: :create
  validate :parent_cannot_be_self
  validate :parent_must_be_top_level
  validate :inbox_ids_within_parent_scope
  validate :inbox_ids_cover_subcategories

  scope :active, -> { where(is_active: true) }
  scope :top_level, -> { where(parent_id: nil) }
  # Categorias sin subcategorias propias -- las unicas que de verdad
  # matchean contenido (ver Auditoria::KeywordCategoryMatcherService y
  # Auditoria::ConversationAnalyzerCategoryMatching#active_ai_categories).
  # Una categoria "padre" (ej. "Competencia") es solo una agrupacion visual
  # en el reporte; su conteo es la suma de sus subcategorias, nunca matchea
  # directamente.
  scope :leaf, -> { where.not(id: Auditoria::Category.where.not(parent_id: nil).select(:parent_id)) }

  def subcategories?
    subcategories.exists?
  end

  # Maximo 2 niveles de profundidad por diseño (ver seccion "parent" del
  # formulario de categorias: solo ofrece categorias top_level como
  # opciones de padre) -- por eso alcanza con los hijos directos, nunca
  # hace falta recursividad real.
  def descendant_ids
    subcategories.ids
  end

  # Mismo formato que el viejo sistema (keyword_configurations.search_terms):
  # texto separado por coma o salto de linea, parseado al momento de armar
  # el regex (ver Auditoria::KeywordCategoryMatcherService).
  def search_terms_list
    search_terms.to_s.split(/[\n,]/).map(&:strip).reject(&:blank?)
  end

  def scoped_to_all_inboxes?
    inbox_ids.blank?
  end

  def applies_to_inbox?(inbox_id)
    scoped_to_all_inboxes? || inbox_ids.include?(inbox_id)
  end

  # Patron compartido para matchear un termino configurado como palabra
  # completa (\y = boundary de Postgres), usado tanto para decidir si un
  # mensaje matchea (Auditoria::KeywordCategoryMatcherService) como para
  # reconstruir cual termino especifico disparo una mencion ya guardada
  # (V2::Reports::AuditoriaCategoryTermsBuilder/...ConversationsBuilder).
  def self.term_pattern(term)
    "\\y#{Regexp.escape(term)}\\y"
  end

  # Mismo termino, version Ruby (\y de Postgres no es un token valido en el
  # motor de regex de Ruby) -- usado para re-evaluar texto ya traido a Ruby
  # (transcripciones de audio, reconstruir que termino disparo una mencion
  # ya guardada), nunca contra SQL directo (ver .term_pattern para eso).
  def self.term_regex(term)
    /\b#{Regexp.escape(term)}\b/i
  end

  private

  def max_categories_per_account
    return if account.blank?
    return if account.auditoria_categories.count < MAX_CATEGORIES_PER_ACCOUNT

    errors.add(:base, I18n.t('auditoria.max_categories_reached', limit: MAX_CATEGORIES_PER_ACCOUNT))
  end

  def parent_cannot_be_self
    errors.add(:parent, :invalid) if parent_id.present? && parent_id == id
  end

  # Maximo 2 niveles por diseño (ver descendant_ids) -- una subcategoria
  # nunca puede a su vez ser padre de otra, sin importar que la UI ya
  # restrinja el selector de "categoria padre" a solo categorias
  # top_level; esto cubre llamadas directas a la API.
  def parent_must_be_top_level
    errors.add(:parent, :invalid) if parent.present? && parent.parent_id.present?
  end

  # El scope de una subcategoria siempre debe ser subconjunto del scope de
  # su padre -- si el padre esta restringido a ciertos inbox, la subcategoria
  # no puede ser "todos los inboxes" ni incluir uno fuera de ese conjunto.
  def inbox_ids_within_parent_scope
    return if parent.blank? || parent.scoped_to_all_inboxes?
    return if !scoped_to_all_inboxes? && (inbox_ids - parent.inbox_ids).empty?

    errors.add(:inbox_ids, I18n.t('auditoria.category_scope_narrower_than_parent_required', parent_title: parent.title))
  end

  # El inverso: si una categoria ya tiene subcategorias, achicar su scope no
  # puede dejar a alguna de ellas por fuera (ej. padre pasa de "todos" a solo
  # inbox X mientras una subcategoria sigue en "todos" o en el inbox Y).
  def inbox_ids_cover_subcategories
    return if scoped_to_all_inboxes? || !persisted?

    conflicting = subcategories.reject { |child| !child.scoped_to_all_inboxes? && (child.inbox_ids - inbox_ids).empty? }
    return if conflicting.empty?

    errors.add(:inbox_ids, I18n.t('auditoria.category_scope_conflicts_with_subcategories', titles: conflicting.map(&:title).join(', ')))
  end
end

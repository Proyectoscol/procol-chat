# == Schema Information
#
# Table name: auditoria_categories
#
#  id           :bigint           not null, primary key
#  instructions :text
#  is_active    :boolean          default(TRUE), not null
#  match_type   :integer          default("keyword"), not null
#  search_terms :text
#  title        :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
# Indexes
#
#  index_auditoria_categories_on_account_and_title  (account_id,title) UNIQUE
#  index_auditoria_categories_on_account_id         (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Auditoria::Category < ApplicationRecord
  self.table_name = 'auditoria_categories'

  MAX_CATEGORIES_PER_ACCOUNT = 10

  belongs_to :account
  has_many :auditoria_category_mentions, class_name: 'Auditoria::CategoryMention', dependent: :destroy

  enum :match_type, { keyword: 0, ai: 1 }, prefix: true

  validates :title, presence: true, uniqueness: { scope: :account_id }
  validate :max_categories_per_account, on: :create

  scope :active, -> { where(is_active: true) }

  # Mismo formato que el viejo sistema (keyword_configurations.search_terms):
  # texto separado por coma o salto de linea, parseado al momento de armar
  # el regex (ver Auditoria::KeywordCategoryMatcherService).
  def search_terms_list
    search_terms.to_s.split(/[\n,]/).map(&:strip).reject(&:blank?)
  end

  private

  def max_categories_per_account
    return if account.blank?
    return if account.auditoria_categories.count < MAX_CATEGORIES_PER_ACCOUNT

    errors.add(:base, I18n.t('auditoria.max_categories_reached', limit: MAX_CATEGORIES_PER_ACCOUNT))
  end
end

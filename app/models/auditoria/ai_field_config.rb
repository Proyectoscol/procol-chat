# == Schema Information
#
# Table name: auditoria_ai_field_configs
#
#  id          :bigint           not null, primary key
#  field_order :integer          not null
#  is_active   :boolean          default(TRUE), not null
#  subtitle    :text
#  title       :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_auditoria_ai_field_configs_on_account_and_order  (account_id,field_order) UNIQUE
#  index_auditoria_ai_field_configs_on_account_id         (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Auditoria::AiFieldConfig < ApplicationRecord
  self.table_name = 'auditoria_ai_field_configs'

  belongs_to :account

  validates :field_order, presence: true, uniqueness: { scope: :account_id }
  validates :title, presence: true

  default_scope { order(:field_order) }
  scope :active, -> { where(is_active: true) }

  DEFAULTS = [
    { title: 'Resumen' },
    { title: 'Tono Emocional' },
    { title: 'Recomendación de Experto' },
    { title: 'Objeciones' },
    { title: 'Opinión de Experto' }
  ].freeze
end

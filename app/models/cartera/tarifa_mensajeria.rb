# Costo por mensaje de WhatsApp segun la categoria que aprobo Meta
# (utility/marketing/authentication). El correo no tiene tarifa - su costo
# estimado siempre es 0.
# == Schema Information
#
# Table name: cartera_tarifas_mensajeria
#
#  id             :bigint           not null, primary key
#  actualizado_at :datetime         not null
#  categoria      :string           not null
#  costo          :decimal(10, 4)   not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_cartera_tarifas_mensajeria_on_account_id                (account_id)
#  index_cartera_tarifas_mensajeria_on_account_id_and_categoria  (account_id,categoria) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Cartera::TarifaMensajeria < ApplicationRecord
  self.table_name = 'cartera_tarifas_mensajeria'

  CATEGORIAS = %w[marketing utility authentication].freeze

  belongs_to :account

  validates :categoria, inclusion: { in: CATEGORIAS }
  validates :costo, numericality: { greater_than_or_equal_to: 0 }
  validates :categoria, uniqueness: { scope: :account_id }

  before_validation :set_actualizado_at

  private

  def set_actualizado_at
    self.actualizado_at = Time.current if costo_changed? || new_record?
  end
end

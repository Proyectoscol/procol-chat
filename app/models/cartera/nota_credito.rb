# == Schema Information
#
# Table name: cartera_notas_credito
#
#  id          :bigint           not null, primary key
#  fecha       :datetime         not null
#  motivo      :string
#  valor       :decimal(18, 2)   not null
#  created_at  :datetime         not null
#  account_id  :bigint           not null
#  external_id :string           not null
#  factura_id  :bigint           not null
#
# Indexes
#
#  index_cartera_notas_credito_on_account_id                  (account_id)
#  index_cartera_notas_credito_on_account_id_and_external_id  (account_id,external_id) UNIQUE
#  index_cartera_notas_credito_on_factura_id                  (factura_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (factura_id => cartera_facturas.id) ON DELETE => cascade
#
class Cartera::NotaCredito < ApplicationRecord
  self.table_name = 'cartera_notas_credito'

  belongs_to :account
  belongs_to :factura, class_name: 'Cartera::Factura', inverse_of: :notas_credito

  validates :external_id, :valor, :fecha, presence: true
  validates :external_id, uniqueness: { scope: :account_id }
end

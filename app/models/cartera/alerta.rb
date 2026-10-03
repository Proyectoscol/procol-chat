# == Schema Information
#
# Table name: cartera_alertas
#
#  id              :bigint           not null, primary key
#  fecha_limite    :datetime
#  leida           :boolean          default(FALSE), not null
#  mensaje         :text             not null
#  tipo            :string           not null
#  util            :boolean
#  valor_en_riesgo :decimal(18, 2)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  cliente_id      :bigint
#  factura_id      :bigint
#
# Indexes
#
#  index_cartera_alertas_on_account_id                          (account_id)
#  index_cartera_alertas_on_account_id_and_tipo_and_factura_id  (account_id,tipo,factura_id) UNIQUE
#  index_cartera_alertas_on_cliente_id                          (cliente_id)
#  index_cartera_alertas_on_factura_id                          (factura_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (cliente_id => cartera_clientes.id) ON DELETE => cascade
#  fk_rails_...  (factura_id => cartera_facturas.id) ON DELETE => cascade
#
class Cartera::Alerta < ApplicationRecord
  self.table_name = 'cartera_alertas'

  belongs_to :account
  belongs_to :cliente, class_name: 'Cartera::Cliente', optional: true, inverse_of: :alertas
  belongs_to :factura, class_name: 'Cartera::Factura', optional: true, inverse_of: :alertas

  validates :tipo, :mensaje, presence: true
  validates :tipo, uniqueness: { scope: [:account_id, :factura_id] }
end

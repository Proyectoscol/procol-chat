# == Schema Information
#
# Table name: cartera_facturas
#
#  id                      :bigint           not null, primary key
#  cufe                    :string
#  fecha_emision           :datetime         not null
#  fecha_vencimiento       :datetime         not null
#  numero                  :string           not null
#  saldo_pendiente         :decimal(18, 2)   not null
#  ultimo_tramo_notificado :integer
#  valor_total             :decimal(18, 2)   not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  cliente_id              :bigint           not null
#  external_id             :string           not null
#
# Indexes
#
#  index_cartera_facturas_on_account_id                        (account_id)
#  index_cartera_facturas_on_account_id_and_cliente_id         (account_id,cliente_id)
#  index_cartera_facturas_on_account_id_and_external_id        (account_id,external_id) UNIQUE
#  index_cartera_facturas_on_account_id_and_fecha_vencimiento  (account_id,fecha_vencimiento)
#  index_cartera_facturas_on_cliente_id                        (cliente_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (cliente_id => cartera_clientes.id) ON DELETE => cascade
#
class Cartera::Factura < ApplicationRecord
  self.table_name = 'cartera_facturas'

  enum :ultimo_tramo_notificado,
       { vigente: 0, d1_30: 1, d31_60: 2, d61_90: 3, d91_180: 4, d181_360: 5, mas_360: 6 },
       allow_nil: true

  belongs_to :account
  belongs_to :cliente, class_name: 'Cartera::Cliente', inverse_of: :facturas
  has_many :aplicaciones_pago, class_name: 'Cartera::AplicacionPago', dependent: :destroy, inverse_of: :factura
  has_many :notas_credito, class_name: 'Cartera::NotaCredito', dependent: :destroy, inverse_of: :factura
  has_many :eventos_radian, class_name: 'Cartera::EventoRadian', dependent: :destroy, inverse_of: :factura
  has_many :alertas, class_name: 'Cartera::Alerta', dependent: :destroy, inverse_of: :factura

  validates :external_id, :numero, :fecha_emision, :fecha_vencimiento, :valor_total, :saldo_pendiente, presence: true
  validates :external_id, uniqueness: { scope: :account_id }
end

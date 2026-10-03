# == Schema Information
#
# Table name: cartera_casos
#
#  id                         :bigint           not null, primary key
#  descartado                 :boolean          default(FALSE), not null
#  dias_vencido_max           :integer
#  estado                     :string           default("abierto"), not null
#  factores_score             :jsonb
#  facturas_abiertas_cantidad :integer
#  fecha_primera_factura      :datetime
#  nivel_escalamiento         :string           default("persuasivo"), not null
#  no_cobrar                  :boolean          default(FALSE), not null
#  prioridad_score            :decimal(10, 4)
#  puntaje_riesgo             :integer
#  razon_no_cobrar            :string
#  revisado                   :boolean          default(FALSE), not null
#  saldo_abierto              :decimal(18, 2)
#  score_credito              :integer
#  total_facturado_historico  :decimal(18, 2)
#  tramo                      :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  cliente_id                 :bigint           not null
#
# Indexes
#
#  index_cartera_casos_on_account_id                 (account_id)
#  index_cartera_casos_on_account_id_and_cliente_id  (account_id,cliente_id) UNIQUE
#  index_cartera_casos_on_cliente_id                 (cliente_id)
#  index_cartera_casos_on_prioridad_score            (prioridad_score)
#  index_cartera_casos_on_puntaje_riesgo             (puntaje_riesgo)
#  index_cartera_casos_on_saldo_abierto              (saldo_abierto)
#  index_cartera_casos_on_tramo                      (tramo)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (cliente_id => cartera_clientes.id) ON DELETE => cascade
#
class Cartera::Caso < ApplicationRecord
  self.table_name = 'cartera_casos'

  belongs_to :account
  belongs_to :cliente, class_name: 'Cartera::Cliente', inverse_of: :caso

  validates :estado, :nivel_escalamiento, presence: true
  validates :cliente_id, uniqueness: { scope: :account_id }
end

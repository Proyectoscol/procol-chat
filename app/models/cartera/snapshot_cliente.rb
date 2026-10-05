# Fotografia periodica del estado de cartera de un cliente - ver comentario
# de la migracion para el razonamiento completo.
# == Schema Information
#
# Table name: cartera_snapshots_cliente
#
#  id                         :bigint           not null, primary key
#  dias_vencido_max           :integer
#  facturas_abiertas_cantidad :integer
#  fecha_snapshot             :datetime         not null
#  nivel_escalamiento         :string
#  no_cobrar                  :boolean          default(FALSE), not null
#  puntaje_riesgo             :integer
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
#  idx_snapshots_cliente_unico_por_fecha          (account_id,cliente_id,fecha_snapshot) UNIQUE
#  index_cartera_snapshots_cliente_on_account_id  (account_id)
#  index_cartera_snapshots_cliente_on_cliente_id  (cliente_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (cliente_id => cartera_clientes.id) ON DELETE => cascade
#
class Cartera::SnapshotCliente < ApplicationRecord
  self.table_name = 'cartera_snapshots_cliente'

  belongs_to :account
  belongs_to :cliente, class_name: 'Cartera::Cliente', inverse_of: :snapshots

  validates :fecha_snapshot, presence: true
end

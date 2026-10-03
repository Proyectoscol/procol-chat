# == Schema Information
#
# Table name: cartera_pagos
#
#  id          :bigint           not null, primary key
#  fecha       :datetime         not null
#  medio_pago  :string
#  valor       :decimal(18, 2)   not null
#  created_at  :datetime         not null
#  account_id  :bigint           not null
#  cliente_id  :bigint           not null
#  external_id :string           not null
#
# Indexes
#
#  index_cartera_pagos_on_account_id                  (account_id)
#  index_cartera_pagos_on_account_id_and_external_id  (account_id,external_id) UNIQUE
#  index_cartera_pagos_on_cliente_id                  (cliente_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (cliente_id => cartera_clientes.id) ON DELETE => cascade
#
class Cartera::Pago < ApplicationRecord
  self.table_name = 'cartera_pagos'

  belongs_to :account
  belongs_to :cliente, class_name: 'Cartera::Cliente', inverse_of: :pagos
  has_many :aplicaciones_pago, class_name: 'Cartera::AplicacionPago', dependent: :destroy, inverse_of: :pago

  validates :external_id, :fecha, :valor, presence: true
  validates :external_id, uniqueness: { scope: :account_id }
end

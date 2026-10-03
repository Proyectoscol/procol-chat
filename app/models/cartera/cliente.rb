# == Schema Information
#
# Table name: cartera_clientes
#
#  id             :bigint           not null, primary key
#  cupo_asignado  :decimal(18, 2)
#  email          :string
#  es_estrategico :boolean          default(FALSE), not null
#  grupo_control  :integer
#  identificacion :string           not null
#  nombre         :string           not null
#  sucursal       :string
#  telefono       :string
#  tipo_deudor    :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  contact_id     :bigint
#  external_id    :string           not null
#
# Indexes
#
#  index_cartera_clientes_on_account_id                  (account_id)
#  index_cartera_clientes_on_account_id_and_external_id  (account_id,external_id) UNIQUE
#  index_cartera_clientes_on_contact_id                  (contact_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#
class Cartera::Cliente < ApplicationRecord
  self.table_name = 'cartera_clientes'

  enum :tipo_deudor, { persona_natural: 0, empresa: 1, mixto: 2 }
  enum :grupo_control, { con_sistema: 0, sin_sistema: 1 }

  belongs_to :account
  belongs_to :contact, optional: true
  has_many :facturas, class_name: 'Cartera::Factura', dependent: :destroy, inverse_of: :cliente
  has_many :pagos, class_name: 'Cartera::Pago', dependent: :destroy, inverse_of: :cliente
  has_many :alertas, class_name: 'Cartera::Alerta', dependent: :destroy, inverse_of: :cliente
  has_one :caso, class_name: 'Cartera::Caso', dependent: :destroy, inverse_of: :cliente

  validates :external_id, :identificacion, :nombre, presence: true
  validates :external_id, uniqueness: { scope: :account_id }
end

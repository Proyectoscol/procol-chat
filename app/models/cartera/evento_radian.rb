# == Schema Information
#
# Table name: cartera_eventos_radian
#
#  id          :bigint           not null, primary key
#  fecha       :datetime         not null
#  fuente      :string           not null
#  tipo_evento :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  factura_id  :bigint           not null
#
# Indexes
#
#  idx_cartera_eventos_radian_account_factura_tipo  (account_id,factura_id,tipo_evento) UNIQUE
#  index_cartera_eventos_radian_on_account_id       (account_id)
#  index_cartera_eventos_radian_on_factura_id       (factura_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (factura_id => cartera_facturas.id) ON DELETE => cascade
#
class Cartera::EventoRadian < ApplicationRecord
  self.table_name = 'cartera_eventos_radian'

  enum :tipo_evento, { evento_030: 0, evento_031: 1, evento_032: 2, evento_033: 3, evento_034: 4 }

  belongs_to :account
  belongs_to :factura, class_name: 'Cartera::Factura', inverse_of: :eventos_radian

  validates :fecha, :fuente, presence: true
  validates :tipo_evento, uniqueness: { scope: [:account_id, :factura_id] }
end

# == Schema Information
#
# Table name: cartera_aplicaciones_pago
#
#  id             :bigint           not null, primary key
#  valor_aplicado :decimal(18, 2)   not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  factura_id     :bigint           not null
#  pago_id        :bigint           not null
#
# Indexes
#
#  index_cartera_aplicaciones_pago_on_account_id  (account_id)
#  index_cartera_aplicaciones_pago_on_factura_id  (factura_id)
#  index_cartera_aplicaciones_pago_on_pago_id     (pago_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (factura_id => cartera_facturas.id) ON DELETE => cascade
#  fk_rails_...  (pago_id => cartera_pagos.id) ON DELETE => cascade
#
class Cartera::AplicacionPago < ApplicationRecord
  self.table_name = 'cartera_aplicaciones_pago'

  belongs_to :account
  belongs_to :pago, class_name: 'Cartera::Pago', inverse_of: :aplicaciones_pago
  belongs_to :factura, class_name: 'Cartera::Factura', inverse_of: :aplicaciones_pago

  validates :valor_aplicado, presence: true
end

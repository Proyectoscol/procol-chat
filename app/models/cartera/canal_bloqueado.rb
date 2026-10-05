# Un canal bloqueado para un cliente (fijo sin WhatsApp, numero sin
# WhatsApp, correo rebotado, opt-out, error de Twilio) detiene los intentos
# por ese canal sin afectar al otro.
# == Schema Information
#
# Table name: cartera_canales_bloqueados
#
#  id           :bigint           not null, primary key
#  bloqueado_at :datetime         not null
#  canal        :string           not null
#  codigo_error :string
#  detalle      :text
#  razon        :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  cliente_id   :bigint           not null
#
# Indexes
#
#  idx_on_account_id_cliente_id_canal_356d270b46   (account_id,cliente_id,canal) UNIQUE
#  index_cartera_canales_bloqueados_on_account_id  (account_id)
#  index_cartera_canales_bloqueados_on_cliente_id  (cliente_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (cliente_id => cartera_clientes.id) ON DELETE => cascade
#
class Cartera::CanalBloqueado < ApplicationRecord
  self.table_name = 'cartera_canales_bloqueados'

  CANALES = %w[whatsapp email].freeze
  RAZONES = %w[fijo_no_whatsapp sin_whatsapp email_rebotado opt_out error_twilio].freeze

  belongs_to :account
  belongs_to :cliente, class_name: 'Cartera::Cliente'

  validates :canal, inclusion: { in: CANALES }
  validates :razon, inclusion: { in: RAZONES }
  validates :bloqueado_at, presence: true
  validates :canal, uniqueness: { scope: [:account_id, :cliente_id] }
end

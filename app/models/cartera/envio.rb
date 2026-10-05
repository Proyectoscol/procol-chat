# Un registro por cliente evaluado en cada corrida de campana, enviado o no -
# la bitacora de que hizo el motor y por que. factura_ids + los *_al_enviar
# son una foto del momento del envio, no las facturas abiertas de hoy: un
# cliente puede pagar y volver a atrasarse meses despues con otras facturas,
# y cada envio debe quedar atado a las que lo motivaron.
# == Schema Information
#
# Table name: cartera_envios
#
#  id                         :bigint           not null, primary key
#  canal                      :string
#  categoria_plantilla        :string
#  costo_estimado             :decimal(10, 4)
#  dias_vencido_max_al_enviar :integer
#  estado                     :string           default("programado"), not null
#  factura_ids                :bigint           default([]), not null, is an Array
#  modo_prueba                :boolean          default(FALSE), not null
#  razon_omision              :text
#  resultado                  :string
#  saldo_al_enviar            :decimal(18, 2)
#  tramo_al_enviar            :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  campana_id                 :bigint           not null
#  campana_regla_id           :bigint
#  cliente_id                 :bigint           not null
#  message_id                 :bigint
#
# Indexes
#
#  idx_on_account_id_cliente_id_created_at_4dba3b5ef9  (account_id,cliente_id,created_at)
#  index_cartera_envios_on_account_id                  (account_id)
#  index_cartera_envios_on_campana_id                  (campana_id)
#  index_cartera_envios_on_campana_regla_id            (campana_regla_id)
#  index_cartera_envios_on_cliente_id                  (cliente_id)
#  index_cartera_envios_on_factura_ids                 (factura_ids) USING gin
#  index_cartera_envios_on_message_id                  (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (campana_id => cartera_campanas.id) ON DELETE => cascade
#  fk_rails_...  (campana_regla_id => cartera_campana_reglas.id) ON DELETE => nullify
#  fk_rails_...  (cliente_id => cartera_clientes.id) ON DELETE => cascade
#
class Cartera::Envio < ApplicationRecord
  self.table_name = 'cartera_envios'

  ESTADOS = %w[programado omitido_regla omitido_legal omitido_ia omitido_canal_bloqueado enviado fallido].freeze
  CANALES = %w[whatsapp email].freeze
  RESULTADOS = %w[sin_respuesta promesa_pago recontactar disputa acuerdo_pago pagado no_contactable].freeze

  belongs_to :account
  belongs_to :campana, class_name: 'Cartera::Campana', inverse_of: :envios
  belongs_to :campana_regla, class_name: 'Cartera::CampanaRegla', optional: true
  belongs_to :cliente, class_name: 'Cartera::Cliente'
  belongs_to :message, optional: true

  validates :estado, inclusion: { in: ESTADOS }
  validates :canal, inclusion: { in: CANALES }, allow_nil: true
  validates :resultado, inclusion: { in: RESULTADOS }, allow_nil: true

  before_validation :ensure_account_id

  private

  def ensure_account_id
    self.account_id ||= campana&.account_id
  end
end

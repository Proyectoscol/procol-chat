# Una regla = a quien (condiciones) + con que plantilla en cada canal. La
# primera regla cuyas condiciones coinciden (por orden) gana. No elige el
# canal: el motor de la campana resuelve WhatsApp o correo segun el canal ya
# usado esa semana y la disponibilidad del cliente.
# == Schema Information
#
# Table name: cartera_campana_reglas
#
#  id                             :bigint           not null, primary key
#  accion                         :string           default("enviar"), not null
#  condiciones                    :jsonb            not null
#  orden                          :integer          not null
#  plantilla_whatsapp_content_sid :string
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :bigint           not null
#  campana_id                     :bigint           not null
#  plantilla_email_id             :bigint
#
# Indexes
#
#  index_cartera_campana_reglas_on_account_id            (account_id)
#  index_cartera_campana_reglas_on_campana_id            (campana_id)
#  index_cartera_campana_reglas_on_campana_id_and_orden  (campana_id,orden) UNIQUE
#  index_cartera_campana_reglas_on_plantilla_email_id    (plantilla_email_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (campana_id => cartera_campanas.id) ON DELETE => cascade
#  fk_rails_...  (plantilla_email_id => cartera_plantillas_email.id) ON DELETE => nullify
#
class Cartera::CampanaRegla < ApplicationRecord
  self.table_name = 'cartera_campana_reglas'

  ACCIONES = %w[enviar excluir].freeze

  belongs_to :account
  belongs_to :campana, class_name: 'Cartera::Campana', inverse_of: :reglas
  belongs_to :plantilla_email, class_name: 'Cartera::PlantillaEmail', optional: true

  validates :orden, presence: true, uniqueness: { scope: :campana_id }
  validates :accion, inclusion: { in: ACCIONES }
  validates :condiciones, exclusion: { in: [nil] } # {} es valida: "sin condiciones" = coincide con todos (catch-all)

  before_validation :ensure_account_id

  private

  def ensure_account_id
    self.account_id ||= campana&.account_id
  end
end

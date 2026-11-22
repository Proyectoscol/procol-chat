# Biblioteca de plantillas versionadas (Fase 3 del trabajo de copy de
# WhatsApp): cada "key" (ej. "confirmacion_particular", "no_show") tiene N
# versiones en esta tabla, y SOLO una puede estar "active" a la vez (ver el
# indice unico parcial en la migracion). Calendario::AppointmentEventTrigger
# y los pasos de Calendario::WelcomeBotFlow referencian una key (no un id de
# fila puntual) y siempre resuelven la version activa al momento de enviar
# -- asi activar una v2 cambia el mensaje real sin tocar el trigger/flow, y
# las versiones viejas quedan como historial sin borrarse.
# == Schema Information
#
# Table name: calendario_message_templates
#
#  id            :bigint           not null, primary key
#  body          :text             not null
#  key           :string           not null
#  label         :string           not null
#  notes         :text
#  quick_replies :jsonb            not null
#  status        :string           default("draft"), not null
#  version       :integer          default(1), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_calendario_message_templates_on_account_id           (account_id)
#  index_calendario_message_templates_on_account_key_version  (account_id,key,version) UNIQUE
#  index_one_active_message_template_per_key                  (account_id,key) UNIQUE WHERE ((status)::text = 'active'::text)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Calendario::MessageTemplate < ApplicationRecord
  self.table_name = 'calendario_message_templates'

  STATUSES = %w[draft active].freeze

  belongs_to :account

  validates :key, presence: true
  validates :label, presence: true
  validates :body, presence: true
  validates :version, presence: true, numericality: { greater_than: 0 }
  validates :version, uniqueness: { scope: %i[account_id key] }
  validates :status, inclusion: { in: STATUSES }

  scope :for_key, ->(key) { where(key: key) }
  scope :active, -> { where(status: 'active') }
  scope :ordered, -> { order(key: :asc, version: :desc) }

  def self.next_version_for(account, key)
    for_key(key).where(account: account).maximum(:version).to_i + 1
  end

  # Usado por AppointmentEventTrigger/WelcomeBotAppointmentActions al
  # momento de enviar/renderizar -- blank si la key no existe o no tiene
  # ninguna version activa (el llamador cae de vuelta al texto literal).
  def self.active_body(account, key)
    return if key.blank?

    for_key(key).where(account: account).active.first&.body
  end

  # Desactiva (vuelve "draft") cualquier otra version de la misma key antes
  # de marcar esta como la activa -- nunca pueden quedar dos a la vez
  # (tambien protegido por el indice unico parcial, esto evita la excepcion).
  def activate!
    transaction do
      self.class.for_key(key).where(account_id: account_id).where.not(id: id).find_each { |sibling| sibling.update!(status: 'draft') }
      update!(status: 'active')
    end
  end
end

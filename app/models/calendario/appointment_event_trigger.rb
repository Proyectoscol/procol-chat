# Una sola tabla para los 3 tipos de disparador (ver addendum del
# 2026-10-29 al eng-review de Calendario) en vez de 3 mecanismos ad-hoc --
# asi el runner y el job de antes-de-la-cita no tienen que saber de donde
# vino el disparador, solo de su trigger_kind.
# == Schema Information
#
# Table name: calendario_appointment_event_triggers
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  offset_minutes  :integer
#  target_status   :string
#  template_params :jsonb            not null
#  trigger_kind    :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  inbox_id        :bigint           not null
#  service_id      :bigint
#
# Indexes
#
#  index_calendario_appointment_event_triggers_on_account_id  (account_id)
#  index_calendario_appointment_event_triggers_on_inbox_id    (inbox_id)
#  index_calendario_appointment_event_triggers_on_service_id  (service_id)
#  index_calendario_triggers_on_account_and_kind              (account_id,trigger_kind)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#  fk_rails_...  (service_id => calendario_services.id) ON DELETE => cascade
#
class Calendario::AppointmentEventTrigger < ApplicationRecord
  self.table_name = 'calendario_appointment_event_triggers'

  TRIGGER_KINDS = %w[on_create on_status_change before_start].freeze
  TARGET_STATUSES = %w[pending confirmed attended no_show cancelled].freeze

  belongs_to :account
  belongs_to :service, class_name: 'Calendario::Service', optional: true
  belongs_to :inbox
  has_many :firings, class_name: 'Calendario::AppointmentTriggerFiring', foreign_key: :trigger_id,
                      inverse_of: :trigger, dependent: :destroy

  validates :trigger_kind, inclusion: { in: TRIGGER_KINDS }
  validates :target_status, presence: true, inclusion: { in: TARGET_STATUSES }, if: :on_status_change?
  validates :target_status, absence: true, unless: :on_status_change?
  validates :offset_minutes, presence: true, numericality: { greater_than: 0 }, if: :before_start?
  validates :offset_minutes, absence: true, unless: :before_start?
  validate :inbox_belongs_to_account
  validate :service_belongs_to_account

  scope :active, -> { where(active: true) }
  scope :for_kind, ->(kind) { where(trigger_kind: kind) }

  def on_create?
    trigger_kind == 'on_create'
  end

  def on_status_change?
    trigger_kind == 'on_status_change'
  end

  def before_start?
    trigger_kind == 'before_start'
  end

  # nil service_id = aplica a todos los servicios de la cuenta.
  def applies_to?(appointment)
    service_id.blank? || service_id == appointment.service_id
  end

  private

  def inbox_belongs_to_account
    return if inbox.blank? || inbox.account_id == account_id

    errors.add(:inbox, :invalid)
  end

  def service_belongs_to_account
    return if service.blank? || service.account_id == account_id

    errors.add(:service, :invalid)
  end
end

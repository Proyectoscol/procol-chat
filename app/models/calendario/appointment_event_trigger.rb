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
#  payer_kinds     :string           default([]), not null, is an Array
#  service_ids     :bigint           default([]), not null, is an Array
#  target_status   :string
#  template_params :jsonb            not null
#  test_mode       :boolean          default(FALSE), not null
#  trigger_kind    :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  inbox_id        :bigint           not null
#
# Indexes
#
#  index_calendario_appointment_event_triggers_on_account_id   (account_id)
#  index_calendario_appointment_event_triggers_on_inbox_id     (inbox_id)
#  index_calendario_appointment_event_triggers_on_service_ids  (service_ids) USING gin
#  index_calendario_triggers_on_account_and_kind               (account_id,trigger_kind)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#
class Calendario::AppointmentEventTrigger < ApplicationRecord
  self.table_name = 'calendario_appointment_event_triggers'

  TRIGGER_KINDS = %w[on_create on_status_change before_start].freeze
  TARGET_STATUSES = %w[pending confirmed attended no_show cancelled].freeze

  belongs_to :account
  belongs_to :inbox
  has_many :firings, class_name: 'Calendario::AppointmentTriggerFiring', foreign_key: :trigger_id,
                     inverse_of: :trigger, dependent: :destroy

  validates :trigger_kind, inclusion: { in: TRIGGER_KINDS }
  validates :target_status, presence: true, inclusion: { in: TARGET_STATUSES }, if: :on_status_change?
  validates :target_status, absence: true, unless: :on_status_change?
  validates :offset_minutes, presence: true, numericality: { greater_than: 0 }, if: :before_start?
  # Para on_status_change: minutos DESPUES del cambio de estado antes de
  # mandar el mensaje (ej. "atendida" o "no_show" un rato despues, no al
  # instante) -- pedido explicito del usuario. En blanco = 0 = instantaneo.
  validates :offset_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true, if: :on_status_change?
  validates :offset_minutes, absence: true, if: :on_create?
  validate :inbox_belongs_to_account
  validate :services_belong_to_account
  validate :payer_kinds_are_valid

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

  # En blanco (nil) para on_status_change = 0 = instantaneo.
  def delay_minutes
    offset_minutes.to_i
  end

  # service_ids/payer_kinds vacios = aplica a todos los servicios/tipos de
  # pagador de la cuenta -- mismo convenio que el service_id nulo anterior.
  def applies_to?(appointment)
    (service_ids.blank? || service_ids.include?(appointment.service_id)) &&
      (payer_kinds.blank? || payer_kinds.include?(appointment.contact&.payer&.kind))
  end

  def services
    Calendario::Service.where(id: service_ids)
  end

  private

  def inbox_belongs_to_account
    return if inbox.blank? || inbox.account_id == account_id

    errors.add(:inbox, :invalid)
  end

  def services_belong_to_account
    return if service_ids.blank?

    valid_count = account.calendario_services.where(id: service_ids).count
    return if valid_count == service_ids.uniq.size

    errors.add(:service_ids, :invalid)
  end

  def payer_kinds_are_valid
    return if payer_kinds.blank?
    return if (payer_kinds - Calendario::Payer.kinds.keys).empty?

    errors.add(:payer_kinds, :invalid)
  end
end

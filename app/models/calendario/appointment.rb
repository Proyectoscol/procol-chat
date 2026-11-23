# == Schema Information
#
# Table name: calendario_appointments
#
#  id                               :bigint           not null, primary key
#  ends_at                          :datetime         not null
#  notes                            :text
#  reschedules_count                :integer          default(0), not null
#  returning_patient_prompt_sent_at :datetime
#  starts_at                        :datetime         not null
#  status                           :integer          default("pending"), not null
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  account_id                       :bigint           not null
#  contact_id                       :bigint           not null
#  conversation_id                  :bigint
#  created_by_id                    :bigint
#  professional_id                  :bigint           not null
#  service_id                       :bigint           not null
#
# Indexes
#
#  index_calendario_appointments_on_account_id                (account_id)
#  index_calendario_appointments_on_account_id_and_starts_at  (account_id,starts_at)
#  index_calendario_appointments_on_contact_id                (contact_id)
#  index_calendario_appointments_on_conversation_id           (conversation_id)
#  index_calendario_appointments_on_created_by_id             (created_by_id)
#  index_calendario_appointments_on_professional_id           (professional_id)
#  index_calendario_appointments_on_service_id                (service_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (professional_id => calendario_professionals.id) ON DELETE => cascade
#  fk_rails_...  (service_id => calendario_services.id) ON DELETE => cascade
#
class Calendario::Appointment < ApplicationRecord
  self.table_name = 'calendario_appointments'

  enum :status, { pending: 0, confirmed: 1, attended: 2, no_show: 3, cancelled: 4 }

  belongs_to :account
  belongs_to :professional, class_name: 'Calendario::Professional'
  belongs_to :service, class_name: 'Calendario::Service'
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :audit_logs, -> { order(created_at: :desc) }, class_name: 'Calendario::AppointmentAuditLog', dependent: :destroy

  # Para cargar agendas historicas reales (ej. un Excel de años anteriores
  # migrado al sistema), una sola bandera relaja 3 cosas pensadas para el
  # flujo normal de creacion desde la UI, no para un registro que YA paso:
  #   - starts_at_not_in_past: existe para atrapar errores de digitacion,
  #     no tiene sentido para una fecha que ya ocurrio.
  #   - triggers (webhooks/recordatorios): no deben dispararse para citas
  #     que nunca pasaron por el flujo real -- reenviarian notificaciones
  #     reales sobre citas de hace meses.
  #   - control_requires_prior_history: asume que el "control" se crea
  #     DESPUES de que la consulta/procedimiento previo ya quedo marcado
  #     "atendida" en el sistema -- una carga historica importa todo como
  #     "pending" (no se inventa el desenlace real, ver README del importe)
  #     y por eso nunca tendria historial previo "atendido" que mostrar.
  # Ver data_imports/calendario_agendas_dr_corrales_2026/import_to_local.rb
  attr_accessor :historical_import

  # Fecha/hora anterior, solo mientras corren los triggers on_reschedule del
  # mismo save (ver #run_on_reschedule_triggers) -- Calendario::AppointmentDrop
  # la usa para el texto "se movio de {{ previous_date }} a {{ date }}".
  # saved_change_to_starts_at seguiria disponible igual, pero exponerla asi
  # evita que el drop tenga que conocer la API de dirty-tracking de Rails.
  attr_accessor :rescheduled_from

  before_validation :set_ends_at_from_service, on: :create

  validates :starts_at, :ends_at, presence: true
  validate :ends_at_after_starts_at
  validate :starts_at_not_in_past, on: :create
  validate :professional_offers_service
  validate :professional_belongs_to_account
  validate :contact_belongs_to_account
  validate :control_requires_prior_history, if: -> { service.present? && service.control? }

  scope :for_day, ->(date) { where(starts_at: date.all_day) }
  scope :upcoming, -> { where('starts_at >= ?', Time.current) }

  after_create :log_creation
  after_create :run_on_create_triggers
  after_create :schedule_before_start_triggers
  after_create :consume_available_credit_if_control
  after_update :log_reschedule, if: :saved_change_to_starts_at?
  after_update :run_on_reschedule_triggers, if: :saved_change_to_starts_at?
  after_update :log_status_change, if: :saved_change_to_status?
  after_update :run_on_status_change_triggers, if: :saved_change_to_status?
  after_update :grant_included_session_credits, if: :saved_change_to_status?

  # La EPS/asegurador es un dato del contacto, no de la cita -- la tarifa se
  # calcula contra el pagador actual del paciente.
  def price
    service&.price_for(contact&.payer)
  end

  def confirm!
    update!(status: :confirmed)
  end

  def mark_attended!
    update!(status: :attended)
  end

  def mark_no_show!
    update!(status: :no_show)
  end

  def cancel!
    update!(status: :cancelled)
  end

  private

  def log_creation
    audit_logs.create!(account_id: account_id, user: Current.user, event_type: :created, to_starts_at: starts_at)
  end

  # reschedules_count vive en la propia fila (no cuenta audit_logs en cada
  # lectura) porque este numero se muestra en listas -- contar filas de otra
  # tabla por cada cita en pantalla seria un N+1 directo.
  def log_reschedule
    from_value, to_value = saved_change_to_starts_at
    audit_logs.create!(
      account_id: account_id, user: Current.user, event_type: :rescheduled,
      from_starts_at: from_value, to_starts_at: to_value
    )
    increment!(:reschedules_count)
  end

  def log_status_change
    from_value, to_value = saved_change_to_status
    audit_logs.create!(
      account_id: account_id, user: Current.user, event_type: :status_changed,
      from_status: self.class.statuses[from_value], to_status: self.class.statuses[to_value]
    )
  end

  def applicable_triggers(scope)
    account.calendario_appointment_event_triggers.active.merge(scope).select { |trigger| trigger.applies_to?(self) }
  end

  def run_on_create_triggers
    return if historical_import

    applicable_triggers(Calendario::AppointmentEventTrigger.for_kind('on_create')).each do |trigger|
      Calendario::AppointmentTriggerRunner.new(trigger: trigger, appointment: self).perform
    end
  end

  # Pedido explicito del usuario: "atendida"/"no_show"/vuelta a "pendiente"
  # pueden mandarse unos minutos DESPUES del cambio en vez de al instante
  # (trigger.delay_minutes, en blanco = 0 = inmediato) -- mismo mecanismo de
  # job encolado con wait_until que ya usa schedule_before_start_triggers,
  # solo que contado desde "ahora" en vez de desde starts_at.
  def run_on_status_change_triggers
    applicable_triggers(
      Calendario::AppointmentEventTrigger.for_kind('on_status_change').where(target_status: status)
    ).each do |trigger|
      if trigger.delay_minutes.positive?
        Calendario::AppointmentTriggerReminderJob.set(wait_until: trigger.delay_minutes.minutes.from_now)
                                                  .perform_later(trigger.id, id)
      else
        Calendario::AppointmentTriggerRunner.new(trigger: trigger, appointment: self).perform
      end
    end
  end

  # Siempre instantaneo (ver validacion de offset_minutes en
  # Calendario::AppointmentEventTrigger) -- rescheduled_from se arma aca y
  # se consume en el mismo request, nunca sobrevive a un job encolado (por
  # eso este, a diferencia de run_on_status_change_triggers, nunca usa
  # AppointmentTriggerReminderJob).
  def run_on_reschedule_triggers
    self.rescheduled_from = saved_change_to_starts_at.first
    applicable_triggers(Calendario::AppointmentEventTrigger.for_kind('on_reschedule')).each do |trigger|
      Calendario::AppointmentTriggerRunner.new(trigger: trigger, appointment: self).perform
    end
  ensure
    self.rescheduled_from = nil
  end

  # Un job por trigger por cita, encolado con wait_until -- igual que no hay
  # forma nativa de cancelar un ActiveJob ya encolado en este stack, el job
  # mismo vuelve a chequear el estado de la cita al momento de correr (ver
  # Calendario::AppointmentTriggerRunner#appointment_still_applies?).
  def schedule_before_start_triggers
    return if historical_import

    applicable_triggers(Calendario::AppointmentEventTrigger.for_kind('before_start')).each do |trigger|
      run_at = starts_at - trigger.offset_minutes.minutes
      next if run_at <= Time.current

      Calendario::AppointmentTriggerReminderJob.set(wait_until: run_at).perform_later(trigger.id, id)
    end
  end

  def set_ends_at_from_service
    return if starts_at.blank? || service.blank? || ends_at.present?

    self.ends_at = starts_at + service.duration_minutes.minutes
  end

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, 'must be after starts_at')
  end

  def starts_at_not_in_past
    return if historical_import
    return if starts_at.blank? || starts_at >= Time.current

    errors.add(:starts_at, 'cannot be in the past')
  end

  def professional_offers_service
    return if professional.blank? || service.blank?
    return if professional.services.exists?(id: service_id)

    errors.add(:professional, 'does not offer the selected service')
  end

  def professional_belongs_to_account
    return if professional.blank?
    return if professional.account_id == account_id

    errors.add(:professional, :invalid)
  end

  def contact_belongs_to_account
    return if contact.blank?
    return if contact.account_id == account_id

    errors.add(:contact, :invalid)
  end

  # Un control (seguimiento) no existe "de entrada" -- solo tiene sentido si
  # el contacto ya pago una consulta o un procedimiento antes. Un credito
  # disponible (de un procedimiento que incluye sesiones) tambien habilita.
  def control_requires_prior_history
    return if historical_import
    return if contact.blank?
    return if available_credit.present?
    return if contact.calendario_appointments.attended.where.not(id: id)
                      .joins(:service).merge(Calendario::Service.where(kind: %i[consultation procedure])).exists?

    errors.add(:service, 'requires a prior attended consultation or procedure for this contact')
  end

  def available_credit
    return nil if contact.blank?

    contact.calendario_session_credits.available.first
  end

  def consume_available_credit_if_control
    return unless service.control?

    available_credit&.consume!(self)
  end

  # Idempotente: si la cita pasa por attended -> no_show -> attended de nuevo,
  # no se le regalan sesiones dos veces por el mismo procedimiento.
  def grant_included_session_credits
    return unless attended?
    return unless service.procedure? && service.included_sessions.to_i.positive?
    return if Calendario::ContactSessionCredit.exists?(granted_by_appointment_id: id)

    service.included_sessions.times do
      account.calendario_contact_session_credits.create!(contact: contact, granted_by_appointment: self)
    end
  end
end

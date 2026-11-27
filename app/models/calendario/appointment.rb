# == Schema Information
#
# Table name: calendario_appointments
#
#  id                :bigint           not null, primary key
#  amount_to_collect :integer
#  ends_at           :datetime         not null
#  notes             :text
#  reschedules_count :integer          default(0), not null
#  starts_at         :datetime         not null
#  status            :integer          default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  contact_id        :bigint           not null
#  conversation_id   :bigint
#  created_by_id     :bigint
#  professional_id   :bigint           not null
#  service_id        :bigint           not null
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
  include Events::Types

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
  # Bug real en produccion 2026-11-26 (conversacion de prueba #323): una cita
  # CANCELADA pero con fecha futura seguia apareciendo como "cita existente"
  # en el bot (Calendario::WelcomeBotAppointmentActions#handle_lookup_appointment)
  # -- se le ofrecia Reagendar/Cancelar sobre una cita que ya no existe de
  # verdad. "Proxima" nunca deberia incluir un estado que ya no va a pasar.
  scope :upcoming, -> { where('starts_at >= ?', Time.current).where.not(status: :cancelled) }

  after_create :log_creation
  after_create :run_on_create_triggers
  after_create :schedule_before_start_triggers
  after_create :consume_available_credit_if_control
  after_update :log_reschedule, if: :saved_change_to_starts_at?
  after_update :run_on_reschedule_triggers, if: :saved_change_to_starts_at?
  # Bug real en produccion 2026-11-27: schedule_before_start_triggers solo
  # corria al crear la cita -- si el punto "antes de la cita" ya habia
  # pasado para la hora original (ej. cita creada casi encima de su propia
  # hora), ese job nunca se encolaba, y reagendar a una hora mas tarde no lo
  # recuperaba (nada volvia a llamar a este metodo). Encolar jobs nuevos
  # aqui es seguro aunque ya existiera uno viejo con la hora anterior: el
  # guard already_fired? en el runner evita un envio duplicado si el
  # obsoleto llega a correr primero.
  after_update :schedule_before_start_triggers, if: :saved_change_to_starts_at?
  after_update :log_status_change, if: :saved_change_to_status?
  after_update :run_on_status_change_triggers, if: :saved_change_to_status?
  after_update :grant_included_session_credits, if: :saved_change_to_status?
  # Bug real en produccion 2026-11-27: confirmar una cita por el boton de
  # WhatsApp (bot) cambiaba el estado real en la base de datos, pero el
  # panel lateral de la conversacion seguia mostrando "pendiente" hasta que
  # el agente refrescaba la pagina -- no existia ningun broadcast hacia el
  # frontend para cambios de Calendario::Appointment (a diferencia de
  # Conversation/Contact, que si usan este mismo patron de dispatcher).
  after_update :dispatch_status_changed_event, if: :saved_change_to_status?
  after_update :log_cancellation_to_chat, if: -> { saved_change_to_status? && cancelled? }

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

  # Identifica la ocurrencia especifica de ESTE cambio de estado (no solo la
  # cita) -- lo consulta Calendario::AppointmentTriggerRunner para que la
  # llave de "ya_se_envio" no sea permanente por cita (ver auditoria con
  # Codex 2026-11-27, hallazgo #2).
  def status_change_occurrence_token
    audit_logs.where(event_type: :status_changed).order(:id).last&.id.to_s
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

  # Pedido explicito del usuario (ideas.txt #4): que cancelar una cita NUNCA
  # pierda el rastro en el chat, sin importar desde donde se cancele (boton
  # manual en Agendas, flujo del bot, NoShowReplyListener, etc.) -- por eso
  # vive aqui, en el modelo, y no repetido en cada caller. Algunos de esos
  # callers ya dejan su propia nota con contexto adicional (ej. "via bot de
  # bienvenida", si reactivo lista de espera); esta es el respaldo
  # garantizado, no un reemplazo de esas.
  #
  # Solo aplica si la cita tiene una conversacion asociada -- una cita
  # creada directo desde Agendas (sin abrir desde un chat) puede no tener
  # ninguna, y no hay en que chat dejar el registro.
  def log_cancellation_to_chat
    return if conversation.blank?

    zone = account.reporting_timezone.presence || 'UTC'
    fecha = Calendario::SpanishDateFormatter.long_date_time(starts_at.in_time_zone(zone))
    conversation.messages.create!(
      account: conversation.account, inbox: conversation.inbox, private: true, message_type: :outgoing,
      content: "Cita de #{service.name} con #{professional.name} del #{fecha} fue cancelada."
    )
  end

  def dispatch_status_changed_event
    Rails.configuration.dispatcher.dispatch(APPOINTMENT_STATUS_CHANGED, Time.zone.now, appointment: self)
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
    # Bug real encontrado en auditoria con Codex 2026-11-27: si el token de
    # ocurrencia se recalculara al CORRER el job demorado en vez de al
    # encolarlo, un vaiven de estado durante la espera (ej. "atendida" por
    # error corregido a "no_show" antes de que corriera) haria que el job
    # viejo calculara el token del estado NUEVO (el ultimo audit_log en ese
    # momento) y mandara el mensaje equivocado como si fuera el correcto.
    # Capturarlo aqui, al encolar, lo deja fijo a ESTE cambio de estado
    # especifico.
    token = status_change_occurrence_token
    applicable_triggers(
      Calendario::AppointmentEventTrigger.for_kind('on_status_change').where(target_status: status)
    ).each do |trigger|
      if trigger.delay_minutes.positive?
        Calendario::AppointmentTriggerReminderJob.set(wait_until: trigger.delay_minutes.minutes.from_now)
                                                 .perform_later(trigger.id, id, 0, token)
      else
        Calendario::AppointmentTriggerRunner.new(trigger: trigger, appointment: self, occurrence_token: token).perform
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

    self.ends_at = starts_at + service.duration_minutes_for(professional, contact&.payer).minutes
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

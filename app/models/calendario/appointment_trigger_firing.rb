# Registro de "esto ya se disparo" -- evita reenviar el mismo recordatorio
# si el job antes-de-la-cita reintenta, y es lo que el job antes-de-la-cita
# consulta para saber si ya se encargo de esta cita.
#
# occurrence_token distingue cada OCURRENCIA real del evento (no solo el
# trigger+cita) -- bug real encontrado en auditoria con Codex 2026-11-27:
# sin esto, un segundo reagendado o un confirmada->pendiente->confirmada
# nunca volvia a notificar, porque la fila vieja ya "consumia" la llave para
# siempre. Ver Calendario::AppointmentTriggerRunner#resolved_occurrence_token.
# == Schema Information
#
# Table name: calendario_appointment_trigger_firings
#
#  id               :bigint           not null, primary key
#  fired_at         :datetime         not null
#  occurrence_token :string           default(""), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  appointment_id   :bigint           not null
#  trigger_id       :bigint           not null
#
# Indexes
#
#  index_calendario_appointment_trigger_firings_on_appointment_id  (appointment_id)
#  index_calendario_appointment_trigger_firings_on_trigger_id      (trigger_id)
#  index_calendario_trigger_firings_on_trigger_appt_occurrence     (trigger_id,appointment_id,occurrence_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (appointment_id => calendario_appointments.id) ON DELETE => cascade
#  fk_rails_...  (trigger_id => calendario_appointment_event_triggers.id) ON DELETE => cascade
#
class Calendario::AppointmentTriggerFiring < ApplicationRecord
  self.table_name = 'calendario_appointment_trigger_firings'

  belongs_to :trigger, class_name: 'Calendario::AppointmentEventTrigger'
  belongs_to :appointment, class_name: 'Calendario::Appointment'

  validates :trigger_id, uniqueness: { scope: %i[appointment_id occurrence_token] }
end

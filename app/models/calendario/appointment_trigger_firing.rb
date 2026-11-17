# Registro de "esto ya se disparo" -- evita reenviar el mismo recordatorio
# si el job antes-de-la-cita reintenta, y es lo que el job antes-de-la-cita
# consulta para saber si ya se encargo de esta cita.
# == Schema Information
#
# Table name: calendario_appointment_trigger_firings
#
#  id             :bigint           not null, primary key
#  fired_at       :datetime         not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  appointment_id :bigint           not null
#  trigger_id     :bigint           not null
#
# Indexes
#
#  index_calendario_appointment_trigger_firings_on_appointment_id  (appointment_id)
#  index_calendario_appointment_trigger_firings_on_trigger_id      (trigger_id)
#  index_calendario_trigger_firings_on_trigger_and_appointment     (trigger_id,appointment_id) UNIQUE
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

  validates :trigger_id, uniqueness: { scope: :appointment_id }
end

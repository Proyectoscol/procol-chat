# Bug real encontrado en auditoria con Codex 2026-11-27: la llave de
# "ya se envio" (trigger_id, appointment_id) es permanente durante toda la
# vida de la cita, sin importar cuantas veces se reagenda o cambia de
# estado -- un segundo reagendado, o un confirmada->pendiente->confirmada,
# nunca volvia a notificar. occurrence_token distingue cada ocurrencia real
# del evento (ver Calendario::AppointmentTriggerRunner#resolved_occurrence_token).
class AddOccurrenceTokenToCalendarioAppointmentTriggerFirings < ActiveRecord::Migration[7.1]
  def change
    add_column :calendario_appointment_trigger_firings, :occurrence_token, :string, null: false, default: ''

    remove_index :calendario_appointment_trigger_firings, column: %i[trigger_id appointment_id],
                                                          name: 'index_calendario_trigger_firings_on_trigger_and_appointment'
    add_index :calendario_appointment_trigger_firings, %i[trigger_id appointment_id occurrence_token],
              unique: true, name: 'index_calendario_trigger_firings_on_trigger_appt_occurrence'
  end
end

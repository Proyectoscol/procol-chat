# Elimina por completo la feature "paciente que regresa" -- rediseño
# 2026-11-25, pedido explicito del usuario: esa razon de ser (un paciente
# con agente ya asignado que escribe otro dia) la cubre ahora el mismo
# Triaje general, reenviandose solo cuando el mensaje entrante llega en un
# dia calendario distinto (ver Calendario::WelcomeBotListener).
class DropCalendarioReturningAppointmentPrompt < ActiveRecord::Migration[7.1]
  def change
    drop_table :calendario_returning_appointment_prompt_configs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :active, null: false, default: false
      t.boolean :test_mode, null: false, default: true
      t.string :message_template_key
      t.text :ask_template
      t.jsonb :options, null: false, default: ['Sí, cancelar cita', 'Sí, reagendar', 'Hablar con recepción']
      t.string :content_sid

      t.timestamps
    end
    remove_column :calendario_appointments, :returning_patient_prompt_sent_at, :datetime
  end
end

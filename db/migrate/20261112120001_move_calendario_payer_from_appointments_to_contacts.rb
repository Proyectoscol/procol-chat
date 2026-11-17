class MoveCalendarioPayerFromAppointmentsToContacts < ActiveRecord::Migration[7.1]
  def change
    # La EPS/asegurador es un dato del paciente, no de la cita -- vivia en
    # calendario_appointments por error de diseno inicial. Se mueve a
    # contacts antes de tener datos reales en produccion.
    add_reference :contacts, :payer, foreign_key: { to_table: :calendario_payers, on_delete: :nullify }, index: true
    remove_reference :calendario_appointments, :payer, foreign_key: { to_table: :calendario_payers }, index: true
  end
end

class AddPayerToCalendarioAppointments < ActiveRecord::Migration[7.1]
  def change
    add_reference :calendario_appointments, :payer, foreign_key: { to_table: :calendario_payers, on_delete: :nullify }
  end
end

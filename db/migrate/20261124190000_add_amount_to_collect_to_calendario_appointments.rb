class AddAmountToCollectToCalendarioAppointments < ActiveRecord::Migration[7.1]
  def change
    add_column :calendario_appointments, :amount_to_collect, :integer
  end
end

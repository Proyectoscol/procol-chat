class CreateCalendarioProfessionalAvailabilities < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_professional_availabilities do |t|
      t.references :professional, null: false, foreign_key: { to_table: :calendario_professionals, on_delete: :cascade }
      t.integer :weekdays, array: true, null: false, default: [1, 2, 3, 4, 5]
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end

class CreateAgentAvailabilitySchedules < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_availability_schedules do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.integer :weekdays, array: true, null: false, default: [1, 2, 3, 4, 5]
      t.boolean :active, null: false, default: true
      t.boolean :currently_locked, null: false, default: false

      t.timestamps
    end

    add_index :agent_availability_schedules, [:user_id, :active]
  end
end

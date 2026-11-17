class CreateCalendarioAppointmentEventTriggers < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_appointment_event_triggers do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :service, foreign_key: { to_table: :calendario_services, on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.string :trigger_kind, null: false
      t.string :target_status
      t.integer :offset_minutes
      t.boolean :active, null: false, default: true
      t.jsonb :template_params, null: false, default: {}

      t.timestamps
    end

    add_index :calendario_appointment_event_triggers, [:account_id, :trigger_kind],
              name: 'index_calendario_triggers_on_account_and_kind'

    create_table :calendario_appointment_trigger_firings do |t|
      t.references :trigger, null: false, foreign_key: { to_table: :calendario_appointment_event_triggers, on_delete: :cascade }
      t.references :appointment, null: false, foreign_key: { to_table: :calendario_appointments, on_delete: :cascade }
      t.datetime :fired_at, null: false

      t.timestamps
    end

    add_index :calendario_appointment_trigger_firings, [:trigger_id, :appointment_id], unique: true,
              name: 'index_calendario_trigger_firings_on_trigger_and_appointment'
  end
end

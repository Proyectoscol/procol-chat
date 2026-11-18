class AddServiceIdsAndPayerKindsToCalendarioAppointmentEventTriggers < ActiveRecord::Migration[7.1]
  def up
    add_column :calendario_appointment_event_triggers, :service_ids, :bigint, array: true, default: [], null: false
    add_column :calendario_appointment_event_triggers, :payer_kinds, :string, array: true, default: [], null: false

    execute <<~SQL.squish
      UPDATE calendario_appointment_event_triggers
      SET service_ids = ARRAY[service_id]
      WHERE service_id IS NOT NULL
    SQL

    remove_foreign_key :calendario_appointment_event_triggers, :calendario_services, column: :service_id
    remove_column :calendario_appointment_event_triggers, :service_id

    add_index :calendario_appointment_event_triggers, :service_ids, using: :gin
  end

  def down
    add_column :calendario_appointment_event_triggers, :service_id, :bigint
    add_foreign_key :calendario_appointment_event_triggers, :calendario_services, column: :service_id,
                                                                                  on_delete: :cascade
    add_index :calendario_appointment_event_triggers, :service_id

    execute <<~SQL.squish
      UPDATE calendario_appointment_event_triggers
      SET service_id = service_ids[1]
      WHERE array_length(service_ids, 1) > 0
    SQL

    remove_index :calendario_appointment_event_triggers, :service_ids
    remove_column :calendario_appointment_event_triggers, :service_ids
    remove_column :calendario_appointment_event_triggers, :payer_kinds
  end
end

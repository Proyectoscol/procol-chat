class CreateCalendarioAppointmentAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_appointment_audit_logs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :appointment, null: false, foreign_key: { to_table: :calendario_appointments, on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.integer :event_type, null: false
      t.datetime :from_starts_at
      t.datetime :to_starts_at
      t.integer :from_status
      t.integer :to_status

      t.datetime :created_at, null: false
    end

    add_index :calendario_appointment_audit_logs, [:appointment_id, :event_type],
              name: 'index_calendario_audit_logs_on_appointment_and_event'

    add_column :calendario_appointments, :reschedules_count, :integer, null: false, default: 0
  end
end

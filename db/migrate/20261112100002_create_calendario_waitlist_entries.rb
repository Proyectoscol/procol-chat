class CreateCalendarioWaitlistEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_waitlist_entries do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :professional, null: false, foreign_key: { to_table: :calendario_professionals, on_delete: :cascade }
      t.references :service, null: false, foreign_key: { to_table: :calendario_services, on_delete: :cascade }
      t.references :fulfilled_by_appointment, foreign_key: { to_table: :calendario_appointments, on_delete: :nullify }
      t.integer :status, null: false, default: 0
      t.text :notes

      t.timestamps
    end

    add_index :calendario_waitlist_entries, [:professional_id, :status],
              name: 'index_calendario_waitlist_entries_on_professional_status'
  end
end

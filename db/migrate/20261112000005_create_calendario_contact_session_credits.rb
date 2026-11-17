class CreateCalendarioContactSessionCredits < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_contact_session_credits do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :granted_by_appointment, null: false,
                                              foreign_key: { to_table: :calendario_appointments, on_delete: :cascade }
      t.references :consumed_by_appointment, foreign_key: { to_table: :calendario_appointments, on_delete: :nullify }
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :calendario_contact_session_credits, [:contact_id, :consumed_at],
              name: 'index_calendario_session_credits_on_contact_and_consumed'
  end
end

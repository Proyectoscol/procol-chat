class CreateCalendarioBotSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_bot_sessions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :welcome_bot_flow, null: false,
                                      foreign_key: { to_table: :calendario_welcome_bot_flows, on_delete: :cascade }
      t.integer :current_step, null: false, default: 0
      t.jsonb :answers, null: false, default: {}
      t.integer :reminder_count, null: false, default: 0
      t.datetime :last_prompted_at
      t.string :status, null: false, default: 'active'

      t.timestamps
    end

    # Una sola sesion ACTIVA por conversacion a la vez -- evita que dos
    # flujos de triage corran en paralelo para el mismo chat.
    add_index :calendario_bot_sessions, :conversation_id, unique: true, where: "status = 'active'",
                                                          name: 'index_one_active_bot_session_per_conversation'
  end
end

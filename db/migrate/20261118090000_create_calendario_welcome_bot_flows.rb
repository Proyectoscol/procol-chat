class CreateCalendarioWelcomeBotFlows < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_welcome_bot_flows do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :match_type, null: false, default: 'default'
      t.string :match_value
      t.integer :priority, null: false, default: 0
      t.jsonb :steps, null: false, default: []
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    # Solo puede haber UN flujo "default" activo por bandeja -- si ninguna
    # palabra clave matchea, el mensaje tiene que caer en un unico lugar
    # sin ambiguedad (ver Calendario::WelcomeBotFlow.match_for).
    add_index :calendario_welcome_bot_flows, %i[inbox_id match_type], unique: true,
                                                                      where: "match_type = 'default' AND active = true",
                                                                      name: 'index_one_active_default_flow_per_inbox'
  end
end

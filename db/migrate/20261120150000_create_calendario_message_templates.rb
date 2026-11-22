class CreateCalendarioMessageTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_message_templates do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.string :label, null: false
      t.integer :version, null: false, default: 1
      t.text :body, null: false
      t.jsonb :quick_replies, null: false, default: []
      t.string :status, null: false, default: 'draft'
      t.text :notes

      t.timestamps
    end

    add_index :calendario_message_templates, %i[account_id key version], unique: true,
                                                                         name: 'index_calendario_message_templates_on_account_key_version'
    # Solo una version activa por clave -- es la que de verdad se usa al
    # enviar (ver Calendario::MessageTemplate.active_body); el resto queda
    # como historial de borradores, nunca se borra al activar otra.
    add_index :calendario_message_templates, %i[account_id key], unique: true, where: "status = 'active'",
                                                                 name: 'index_one_active_message_template_per_key'
  end
end

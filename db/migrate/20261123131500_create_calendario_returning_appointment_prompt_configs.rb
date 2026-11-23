class CreateCalendarioReturningAppointmentPromptConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_returning_appointment_prompt_configs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :active, null: false, default: false
      t.boolean :test_mode, null: false, default: true
      t.string :message_template_key
      t.text :ask_template
      t.jsonb :options, null: false, default: ['Sí, cancelar cita', 'Sí, reagendar', 'Hablar con recepción']
      t.string :content_sid

      t.timestamps
    end

    add_index :calendario_returning_appointment_prompt_configs, :inbox_id, unique: true,
                                                                           name: 'index_one_prompt_config_per_inbox'
  end
end

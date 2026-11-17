class CreateImportWhatsappChatBatches < ActiveRecord::Migration[7.1]
  def change
    create_table :import_whatsapp_chat_batches do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :us_sender_name, null: false
      t.string :phone_number, null: false
      t.string :original_filename
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.jsonb :stats, null: false, default: {}
      t.timestamps
    end
  end
end

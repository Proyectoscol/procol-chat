class CreateCarteraPlantillasWhatsapp < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_plantillas_whatsapp do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :nombre, null: false
      t.string :categoria, null: false
      t.string :tipo, null: false, default: 'text'
      t.string :idioma, null: false, default: 'es'
      t.text :cuerpo, null: false
      t.jsonb :variables, default: {}
      t.string :content_sid
      t.string :estado, null: false, default: 'borrador'

      t.timestamps
    end

    add_index :cartera_plantillas_whatsapp, [:account_id, :nombre], unique: true
    add_index :cartera_plantillas_whatsapp, :content_sid
  end
end

class CreateCarteraPlantillasEmail < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_plantillas_email do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :nombre, null: false
      t.string :asunto, null: false
      t.text :cuerpo_html, null: false
      t.jsonb :variables, default: {}

      t.timestamps
    end

    add_index :cartera_plantillas_email, [:account_id, :nombre], unique: true
  end
end

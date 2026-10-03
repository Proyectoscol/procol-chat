class CreateCarteraCorridasSync < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_corridas_sync do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :conector, null: false
      t.datetime :inicio, null: false
      t.datetime :fin
      t.string :estado, null: false, default: 'en_progreso'
      t.integer :registros_procesados, null: false, default: 0
      t.jsonb :errores

      t.timestamps
    end
  end
end

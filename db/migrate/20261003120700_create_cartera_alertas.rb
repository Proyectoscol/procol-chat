class CreateCarteraAlertas < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_alertas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :tipo, null: false
      t.references :cliente, foreign_key: { to_table: :cartera_clientes, on_delete: :cascade }
      t.references :factura, foreign_key: { to_table: :cartera_facturas, on_delete: :cascade }
      t.decimal :valor_en_riesgo, precision: 18, scale: 2
      t.datetime :fecha_limite
      t.text :mensaje, null: false
      t.boolean :leida, null: false, default: false
      # rubocop:disable Rails/ThreeStateBooleanColumn -- null = aun sin calificar, no equivale a false
      t.boolean :util
      # rubocop:enable Rails/ThreeStateBooleanColumn

      t.timestamps
    end

    add_index :cartera_alertas, [:account_id, :tipo, :factura_id], unique: true
  end
end

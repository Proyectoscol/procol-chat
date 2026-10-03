class CreateCarteraNotasCredito < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_notas_credito do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :factura, null: false, foreign_key: { to_table: :cartera_facturas, on_delete: :cascade }
      t.string :external_id, null: false
      t.decimal :valor, precision: 18, scale: 2, null: false
      t.datetime :fecha, null: false
      t.string :motivo

      t.datetime :created_at, null: false
    end

    add_index :cartera_notas_credito, [:account_id, :external_id], unique: true
  end
end

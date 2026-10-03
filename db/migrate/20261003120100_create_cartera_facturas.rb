class CreateCarteraFacturas < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_facturas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :cliente, null: false, foreign_key: { to_table: :cartera_clientes, on_delete: :cascade }
      t.string :external_id, null: false
      t.string :numero, null: false
      t.string :cufe
      t.datetime :fecha_emision, null: false
      t.datetime :fecha_vencimiento, null: false
      t.decimal :valor_total, precision: 18, scale: 2, null: false
      t.decimal :saldo_pendiente, precision: 18, scale: 2, null: false
      t.integer :ultimo_tramo_notificado

      t.timestamps
    end

    add_index :cartera_facturas, [:account_id, :external_id], unique: true
    add_index :cartera_facturas, [:account_id, :cliente_id]
    add_index :cartera_facturas, [:account_id, :fecha_vencimiento]
  end
end

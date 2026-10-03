class CreateCarteraPagos < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_pagos do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :cliente, null: false, foreign_key: { to_table: :cartera_clientes, on_delete: :cascade }
      t.string :external_id, null: false
      t.datetime :fecha, null: false
      t.decimal :valor, precision: 18, scale: 2, null: false
      t.string :medio_pago

      t.datetime :created_at, null: false
    end

    add_index :cartera_pagos, [:account_id, :external_id], unique: true
  end
end

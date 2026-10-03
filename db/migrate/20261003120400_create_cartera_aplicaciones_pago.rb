class CreateCarteraAplicacionesPago < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_aplicaciones_pago do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :pago, null: false, foreign_key: { to_table: :cartera_pagos, on_delete: :cascade }
      t.references :factura, null: false, foreign_key: { to_table: :cartera_facturas, on_delete: :cascade }
      t.decimal :valor_aplicado, precision: 18, scale: 2, null: false

      t.timestamps
    end
  end
end

class CreateCarteraEventosRadian < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_eventos_radian do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :factura, null: false, foreign_key: { to_table: :cartera_facturas, on_delete: :cascade }
      t.integer :tipo_evento, null: false
      t.datetime :fecha, null: false
      t.string :fuente, null: false

      t.timestamps
    end

    add_index :cartera_eventos_radian, %i[account_id factura_id tipo_evento],
              unique: true, name: 'idx_cartera_eventos_radian_account_factura_tipo'
  end
end

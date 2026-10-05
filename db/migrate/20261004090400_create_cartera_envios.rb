# Un registro por cliente evaluado en cada corrida de campana, enviado o no -
# la bitacora completa de "que habria hecho el motor y por que". factura_ids
# + los *_al_enviar son una foto del momento del envio: un cliente puede
# atrasarse, pagar y volver a atrasarse con otras facturas meses despues, y
# cada envio debe quedar atado a las facturas que lo motivaron, no a las
# facturas abiertas de hoy.
#
# message_id es bigint sin foreign_key (igual que captain_message_reports) -
# messages.id es legado tipo integer/serial, no hay FK limpia posible.
class CreateCarteraEnvios < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_envios do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :campana, null: false, foreign_key: { to_table: :cartera_campanas, on_delete: :cascade }
      t.references :campana_regla, foreign_key: { to_table: :cartera_campana_reglas, on_delete: :nullify }
      t.references :cliente, null: false, foreign_key: { to_table: :cartera_clientes, on_delete: :cascade }
      t.bigint :factura_ids, array: true, null: false, default: []
      t.decimal :saldo_al_enviar, precision: 18, scale: 2
      t.string :tramo_al_enviar
      t.integer :dias_vencido_max_al_enviar
      t.string :canal # whatsapp | email
      t.references :message
      t.string :estado, null: false, default: 'programado'
      t.text :razon_omision
      t.string :resultado
      t.string :categoria_plantilla
      t.decimal :costo_estimado, precision: 10, scale: 4

      t.timestamps
    end

    add_index :cartera_envios, :factura_ids, using: :gin
    add_index :cartera_envios, [:account_id, :cliente_id, :created_at]
  end
end

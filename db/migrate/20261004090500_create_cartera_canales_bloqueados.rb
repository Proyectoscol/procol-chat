# Un canal bloqueado para un cliente (fijo sin WhatsApp, numero sin WhatsApp,
# correo rebotado, opt-out, error de Twilio) detiene los intentos por ese
# canal sin afectar al otro - el motor sigue intentando por el canal
# restante en semanas siguientes.
class CreateCarteraCanalesBloqueados < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_canales_bloqueados do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :cliente, null: false, foreign_key: { to_table: :cartera_clientes, on_delete: :cascade }
      t.string :canal, null: false # whatsapp | email
      t.string :razon, null: false # fijo_no_whatsapp | sin_whatsapp | email_rebotado | opt_out | error_twilio
      t.string :codigo_error
      t.text :detalle
      t.datetime :bloqueado_at, null: false

      t.timestamps
    end

    add_index :cartera_canales_bloqueados, [:account_id, :cliente_id, :canal], unique: true
  end
end

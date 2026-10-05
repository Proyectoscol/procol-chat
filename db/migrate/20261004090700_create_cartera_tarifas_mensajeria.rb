# Tarifa por categoria de plantilla de WhatsApp (Meta cambia este precio por
# pais/categoria periodicamente) - se mantiene aqui como configuracion que
# el usuario actualiza contra el tarifario vigente, nunca como constante en
# codigo ni leida de Twilio (no la expone de forma confiable).
class CreateCarteraTarifasMensajeria < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_tarifas_mensajeria do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :categoria, null: false
      t.decimal :costo, precision: 10, scale: 4, null: false
      t.datetime :actualizado_at, null: false

      t.timestamps
    end

    add_index :cartera_tarifas_mensajeria, [:account_id, :categoria], unique: true
  end
end

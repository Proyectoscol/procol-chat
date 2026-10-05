# La regla no elige el canal: lleva una plantilla para cada canal y el motor
# de la campana resuelve cual usar segun la disponibilidad del cliente y el
# canal ya usado esa semana. El content_sid de WhatsApp vive en Twilio (via
# el espejo channel.content_templates) - aqui solo se referencia.
class CreateCarteraCampanaReglas < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_campana_reglas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :campana, null: false, foreign_key: { to_table: :cartera_campanas, on_delete: :cascade }
      t.integer :orden, null: false
      t.string :accion, null: false, default: 'enviar' # enviar | excluir
      t.jsonb :condiciones, null: false, default: {}
      t.string :plantilla_whatsapp_content_sid
      t.references :plantilla_email, foreign_key: { to_table: :cartera_plantillas_email, on_delete: :nullify }

      t.timestamps
    end

    add_index :cartera_campana_reglas, [:campana_id, :orden], unique: true
  end
end

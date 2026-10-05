# dias_envio usa la convencion de Date#wday (0=domingo..6=sabado), la misma
# que agent_availability_schedules.weekdays - evita inventar otra escala.
class CreateCarteraCampanas < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_campanas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :nombre, null: false
      t.string :estado, null: false, default: 'borrador' # borrador | activa | pausada | archivada
      t.references :inbox_whatsapp, foreign_key: { to_table: :inboxes, on_delete: :nullify }
      t.references :inbox_email, foreign_key: { to_table: :inboxes, on_delete: :nullify }
      t.references :captain_assistant, foreign_key: { to_table: :captain_assistants, on_delete: :nullify }
      t.integer :dias_envio, array: true, null: false, default: []
      t.time :hora_inicio, null: false
      t.time :hora_fin, null: false
      t.string :autorizacion_fuente # politica_privacidad | terminos_condiciones | contrato | otro
      t.text :autorizacion_detalle
      t.bigint :autorizacion_confirmada_por_user_id
      t.datetime :autorizacion_confirmada_at

      t.timestamps
    end

    # Solo puede haber una campana activa a la vez por cuenta.
    add_index :cartera_campanas, :account_id, unique: true, where: "estado = 'activa'", name: 'idx_cartera_campanas_una_activa_por_cuenta'
  end
end

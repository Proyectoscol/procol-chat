# frozen_string_literal: true

class CreateSipIdentities < ActiveRecord::Migration[7.1]
  def change
    create_table :sip_identities do |t|
      t.references :account, null: false, index: true
      t.references :user, null: false, index: true
      t.string :sip_extension, null: false
      t.string :sip_password # v1: estático (encriptado en el modelo); efímero/realtime → fase 2
      t.integer :sip_active_contacts, null: false, default: 0 # multi-dispositivo: nº de registros SIP activos
      t.datetime :sip_last_registered_at # se setea en la transición 0→1 (primer dispositivo)
      t.datetime :sip_absence_alerted_at # se resetea al volver a 1 tras estar en 0
      t.boolean :sip_absence_mode, null: false, default: false # toggle admin "marcar ausente / redirigir"
      t.string :sip_fcm_token # fase 2 Android (FCM)
      t.string :sip_apns_voip_token # fase 2 iOS (APNs PushKit/CallKit)
      t.datetime :sip_push_token_updated_at

      t.timestamps
    end

    # Multi-cliente: la extensión y la identidad son únicas POR cuenta (DEX-2).
    add_index :sip_identities, [:account_id, :sip_extension], unique: true
    add_index :sip_identities, [:account_id, :user_id], unique: true
  end
end

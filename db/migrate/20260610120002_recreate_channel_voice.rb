# frozen_string_literal: true

class RecreateChannelVoice < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_voice do |t|
      t.references :account, null: false, index: true
      t.string :phone_number, null: false # DID principal del trunk (alimenta Call#from_number/to_number)
      # Conexión + reglas de routing, editables por el admin sin migración (DEX-3):
      # ari_host, wss_host, trunk_name, ivr_digit_to_team, shared_numbers,
      # max_queue_size, staging, absence_threshold_days, enable_callback.
      t.jsonb :provider_config, null: false, default: {}

      t.timestamps
    end

    # Multi-cliente: el DID es único por cuenta.
    add_index :channel_voice, [:account_id, :phone_number], unique: true
  end
end

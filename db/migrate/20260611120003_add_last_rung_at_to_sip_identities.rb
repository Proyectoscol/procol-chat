# frozen_string_literal: true

# Puntero de rotación del round-robin de voz (Sip::Routing::Rules::TeamRoundRobinRule).
# Aditiva y nullable: no toca datos existentes ni el timestamp de auditoría updated_at.
# El asesor recién sonado recibe NOW() y pasa al final de la cola (ORDER BY last_rung_at).
class AddLastRungAtToSipIdentities < ActiveRecord::Migration[7.1]
  def change
    add_column :sip_identities, :last_rung_at, :datetime
  end
end

# Marca de tiempo de la primera vez que la campana paso a estado "activa" -
# "semanas activa" en el panel de estadisticas (Cartera::Campana) se calcula
# contra esto, no contra created_at (una campana puede quedarse en borrador
# dias/semanas antes de activarse por primera vez).
class AddActivadaEnToCarteraCampanas < ActiveRecord::Migration[7.1]
  def change
    add_column :cartera_campanas, :activada_en, :datetime
  end
end

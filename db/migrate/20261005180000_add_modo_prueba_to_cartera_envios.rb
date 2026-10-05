# Distingue un envio real de uno creado por Cartera::Campanas::PruebaService
# (entorno de pruebas): mismas compuertas de elegibilidad, pero
# Cartera::Campanas::EnvioWhatsappService/EnvioEmailService lo enrutan a la
# bandeja de pruebas (Channel::Api) en vez de la bandeja real de la
# campana. Vive en cartera_envios, no en cartera_campanas, para que una
# campana activa nunca pueda quedar "en modo prueba" por accidente - cada
# fila decide su propio enrutamiento.
class AddModoPruebaToCarteraEnvios < ActiveRecord::Migration[7.1]
  def change
    add_column :cartera_envios, :modo_prueba, :boolean, null: false, default: false
  end
end

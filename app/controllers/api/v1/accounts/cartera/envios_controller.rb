# Bitacora de una campana: que hizo el motor con cada caso y por que. Solo
# lectura - los envios los crea Cartera::Campanas::CorridaService/EnvioWhatsappService/
# EnvioEmailService, nunca este controller.
class Api::V1::Accounts::Cartera::EnviosController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  def index
    campana = Current.account.cartera_campanas.find(params[:campana_id])
    envios = campana.envios.includes(:cliente).order(created_at: :desc).limit(200)
    render json: envios.map { |envio| envio_json(envio) }
  end

  private

  def envio_json(envio)
    {
      id: envio.id,
      cliente_id: envio.cliente_id,
      nombre_cliente: envio.cliente&.nombre,
      canal: envio.canal,
      estado: envio.estado,
      razon_omision: envio.razon_omision,
      resultado: envio.resultado,
      factura_ids: envio.factura_ids,
      costo_estimado: envio.costo_estimado&.to_f,
      created_at: envio.created_at
    }
  end
end

# El tarifario de WhatsApp es un recurso singular: una fila por categoria
# (marketing/utility/authentication), nunca mas de 3. El usuario lo
# actualiza a mano contra el tarifario vigente de Meta - no se lee de
# Twilio ni se hardcodea en codigo.
class Api::V1::Accounts::Cartera::TarifasMensajeriaController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  before_action :ensure_administrator, only: [:update]

  def show
    render json: tarifas_json
  end

  def update
    tarifas_params.each do |categoria, costo|
      tarifa = Current.account.cartera_tarifas_mensajeria.find_or_initialize_by(categoria: categoria)
      tarifa.update!(costo: costo)
    end
    render json: tarifas_json
  end

  private

  def tarifas_params
    params.require(:tarifas).permit(*Cartera::TarifaMensajeria::CATEGORIAS).to_h
  end

  def tarifas_json
    existentes = Current.account.cartera_tarifas_mensajeria.index_by(&:categoria)
    {
      tarifas: Cartera::TarifaMensajeria::CATEGORIAS.map do |categoria|
        tarifa = existentes[categoria]
        { categoria: categoria, costo: tarifa&.costo&.to_f, actualizado_at: tarifa&.actualizado_at }
      end
    }
  end

  def ensure_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end

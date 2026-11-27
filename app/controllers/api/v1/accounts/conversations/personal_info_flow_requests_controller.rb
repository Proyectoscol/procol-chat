# Boton "Solicitar datos" en el panel de contacto -- manda la plantilla de
# WhatsApp Flow que pide nombre/documento/EPS/etc. Ver
# Calendario::SendPersonalInfoFlowService.
class Api::V1::Accounts::Conversations::PersonalInfoFlowRequestsController < Api::V1::Accounts::Conversations::BaseController
  def create
    result = Calendario::SendPersonalInfoFlowService.new(conversation: @conversation).perform
    return render(json: { error: result[:error] }, status: :unprocessable_entity) unless result[:success]

    render json: { success: true }
  end
end

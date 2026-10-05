class Api::V1::Accounts::Cartera::CampanasController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  before_action :ensure_administrator, only: [:create, :update]
  before_action :set_campana, only: [:show, :update, :simulacion]

  def index
    render json: Current.account.cartera_campanas.order(created_at: :desc)
  end

  def show
    render json: @campana
  end

  def create
    campana = Current.account.cartera_campanas.new(campana_params)
    campana.save!
    render json: campana, status: :created
  end

  def update
    @campana.update!(campana_params)
    render json: @campana
  end

  # Corrida en seco: no envia nada, no escribe cartera_envios. Cualquier
  # agente con acceso a cartera puede correrla, no solo administradores -
  # es de solo lectura.
  def simulacion
    render json: Cartera::Campanas::SimulacionService.new(campana: @campana).call
  end

  private

  def set_campana
    @campana = Current.account.cartera_campanas.find(params[:id])
  end

  def campana_params
    params.require(:campana).permit(
      :nombre, :estado, :inbox_whatsapp_id, :inbox_email_id, :captain_assistant_id,
      :hora_inicio, :hora_fin, :autorizacion_fuente, :autorizacion_detalle,
      dias_envio: []
    ).tap { |p| confirmar_autorizacion(p) }
  end

  # Confirmar la autorizacion es un acto del usuario que esta guardando el
  # cambio, no un campo que el cliente pueda mandar desde el formulario.
  def confirmar_autorizacion(permitted)
    return if permitted[:autorizacion_fuente].blank?

    permitted[:autorizacion_confirmada_por_user_id] = Current.user.id
    permitted[:autorizacion_confirmada_at] = Time.current
  end

  def ensure_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end

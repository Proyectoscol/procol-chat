class Api::V1::Accounts::Cartera::CampanaReglasController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  before_action :ensure_administrator
  before_action :set_campana
  before_action :set_regla, only: [:update, :destroy]

  def index
    render json: @campana.reglas
  end

  def create
    regla = @campana.reglas.new(regla_params)
    regla.save!
    render json: regla, status: :created
  end

  def update
    @regla.update!(regla_params)
    render json: @regla
  end

  def destroy
    @regla.destroy!
    head :no_content
  end

  private

  def set_campana
    @campana = Current.account.cartera_campanas.find(params[:campana_id])
  end

  def set_regla
    @regla = @campana.reglas.find(params[:id])
  end

  def regla_params
    params.require(:regla).permit(:orden, :accion, :plantilla_whatsapp_content_sid, :plantilla_email_id, condiciones: {})
  end

  def ensure_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end

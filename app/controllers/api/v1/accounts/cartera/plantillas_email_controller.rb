class Api::V1::Accounts::Cartera::PlantillasEmailController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  before_action :ensure_administrator, only: [:create, :update, :destroy]

  def index
    render json: Current.account.cartera_plantillas_email.order(created_at: :desc)
  end

  def create
    plantilla = Current.account.cartera_plantillas_email.new(plantilla_params)
    plantilla.save!
    render json: plantilla, status: :created
  end

  def update
    plantilla = Current.account.cartera_plantillas_email.find(params[:id])
    plantilla.update!(plantilla_params)
    render json: plantilla
  end

  def destroy
    Current.account.cartera_plantillas_email.find(params[:id]).destroy!
    head :no_content
  end

  private

  def plantilla_params
    params.require(:plantilla).permit(:nombre, :asunto, :cuerpo_html, variables: {})
  end

  def ensure_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end

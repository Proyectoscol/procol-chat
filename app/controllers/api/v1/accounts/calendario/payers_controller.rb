class Api::V1::Accounts::Calendario::PayersController < Api::V1::Accounts::BaseController
  wrap_parameters :payer, include: %i[name kind active]

  before_action :check_authorization
  before_action :fetch_payer, only: [:update, :destroy]

  def index
    render json: Current.account.calendario_payers.order(:kind, :name).map { |payer| serialize(payer) }
  end

  def create
    payer = Current.account.calendario_payers.create!(payer_params)
    render json: serialize(payer)
  end

  def update
    @payer.update!(payer_params)
    render json: serialize(@payer)
  end

  def destroy
    @payer.destroy!
    head :no_content
  end

  private

  def fetch_payer
    @payer = Current.account.calendario_payers.find(params[:id])
  end

  def payer_params
    params.require(:payer).permit(:name, :kind, :active)
  end

  def serialize(payer)
    { id: payer.id, name: payer.name, kind: payer.kind, active: payer.active }
  end

  def check_authorization
    authorize(:'calendario/payers')
  end
end

class Api::V1::Accounts::Calendario::ServicePricesController < Api::V1::Accounts::BaseController
  wrap_parameters :price, include: %i[payer_id price copago]

  before_action :check_authorization
  before_action :fetch_service
  before_action :fetch_price, only: [:update, :destroy]

  def index
    render json: @service.prices.map { |price| serialize(price) }
  end

  def create
    price = @service.prices.create!(price_params)
    render json: serialize(price)
  end

  def update
    @price.update!(price_params)
    render json: serialize(@price)
  end

  def destroy
    @price.destroy!
    head :no_content
  end

  private

  def fetch_service
    @service = Current.account.calendario_services.find(params[:service_id])
  end

  def fetch_price
    @price = @service.prices.find(params[:id])
  end

  def price_params
    params.require(:price).permit(:payer_id, :price, :copago)
  end

  def serialize(price)
    { id: price.id, payer_id: price.payer_id, payer_name: price.payer&.name, price: price.price, copago: price.copago }
  end

  def check_authorization
    authorize(:'calendario/service_prices')
  end
end

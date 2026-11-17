class Api::V1::Accounts::Calendario::ContactCreditsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    contact = Current.account.contacts.find(params[:contact_id])
    render json: { available_count: contact.calendario_session_credits.available.count }
  end

  private

  def check_authorization
    authorize(:'calendario/contact_credits')
  end
end

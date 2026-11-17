class Api::V1::Accounts::Calendario::StatsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    render json: Calendario::AppointmentStatsService.new(
      account: Current.account, range_since: parsed_since, range_until: parsed_until, professional_id: params[:professional_id],
      group_by: params[:group_by].presence || 'starts_at'
    ).perform
  end

  private

  def parsed_since
    Time.zone.parse(params[:since])
  end

  def parsed_until
    Time.zone.parse(params[:until])
  end

  def check_authorization
    authorize(:'calendario/stats')
  end
end

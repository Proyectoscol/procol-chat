class Api::V1::Accounts::TeamsController < Api::V1::Accounts::BaseController
  before_action :fetch_team, only: [:show, :update, :destroy]
  before_action :check_authorization
  before_action :ensure_not_mirrored, only: [:update, :destroy]

  def index
    @teams = Current.account.teams
  end

  def show; end

  def create
    @team = Current.account.teams.new(team_params)
    @team.save!
  end

  def update
    @team.update!(team_params)
  end

  def destroy
    @team.destroy!
    head :ok
  end

  private

  def fetch_team
    @team = Current.account.teams.find(params[:id])
  end

  def ensure_not_mirrored
    raise CustomExceptions::Team::MirroredFromInbox.new({}) if @team.mirrors_inbox?
  end

  def team_params
    params.require(:team).permit(:name, :description, :allow_auto_assign, :icon, :icon_color)
  end
end

# Keeps a 1:1 "mirror" Team in sync with this inbox's name and collaborators
# (see InboxMember's sync callbacks for the membership side). The mirror
# team is not manually editable - see Team#mirrors_inbox? and
# TeamsController/TeamMembersController.
module InboxMirrorTeam
  extend ActiveSupport::Concern

  included do
    has_one :mirror_team, class_name: 'Team', inverse_of: :inbox, dependent: :destroy

    after_create :create_mirror_team
    after_update :sync_mirror_team_name, if: :saved_change_to_name?
  end

  private

  def create_mirror_team
    account.teams.create!(name: name, inbox: self)
  end

  def sync_mirror_team_name
    mirror_team&.update!(name: name)
  end
end

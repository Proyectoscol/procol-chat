# frozen_string_literal: true

namespace :teams do
  desc 'Crea/sincroniza el equipo espejo de cada inbox existente para una cuenta (ACCOUNT_ID=<id>)'
  task backfill_mirror_teams: :environment do
    account_id = ENV['ACCOUNT_ID'].presence
    raise 'Pasa el account_id: rake teams:backfill_mirror_teams ACCOUNT_ID=1' if account_id.blank?

    account = Account.find(account_id)

    created = 0
    synced = 0
    account.inboxes.find_each do |inbox|
      team = inbox.mirror_team
      team ||= account.teams.create!(name: inbox.name, inbox: inbox).tap { created += 1 }

      current_member_ids = team.members.pluck(:id)
      inbox_member_ids = inbox.members.pluck(:id)
      team.add_members(inbox_member_ids - current_member_ids)
      team.remove_members(current_member_ids - inbox_member_ids)
      synced += 1
    end

    puts "Equipos espejo creados: #{created}"
    puts "Equipos espejo sincronizados (incluye los recien creados): #{synced}"
  end
end

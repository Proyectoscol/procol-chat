# frozen_string_literal: true

namespace :teams do
  desc 'Crea/sincroniza el equipo espejo de cada inbox (y etiqueta sus conversaciones) para una cuenta (ACCOUNT_ID=<id>)'
  task backfill_mirror_teams: :environment do
    account_id = ENV['ACCOUNT_ID'].presence
    raise 'Pasa el account_id: rake teams:backfill_mirror_teams ACCOUNT_ID=1' if account_id.blank?

    account = Account.find(account_id)

    created = 0
    synced = 0
    conversations_tagged = 0
    account.inboxes.find_each do |inbox|
      team = inbox.mirror_team
      team ||= account.teams.create!(name: inbox.name, inbox: inbox).tap { created += 1 }

      current_member_ids = team.members.pluck(:id)
      inbox_member_ids = inbox.members.pluck(:id)
      team.add_members(inbox_member_ids - current_member_ids)
      team.remove_members(current_member_ids - inbox_member_ids)
      synced += 1

      # Conversaciones creadas antes de que el inbox tuviera equipo espejo -
      # las nuevas ya se etiquetan solas (ver Conversation#assign_mirror_team).
      conversations_tagged += inbox.conversations.where(team_id: nil).update_all(team_id: team.id) # rubocop:disable Rails/SkipsModelValidations
    end

    puts "Equipos espejo creados: #{created}"
    puts "Equipos espejo sincronizados (incluye los recien creados): #{synced}"
    puts "Conversaciones etiquetadas con su equipo espejo: #{conversations_tagged}"
  end
end

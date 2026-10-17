# frozen_string_literal: true

namespace :auditoria do
  desc 'Verifica agentes sin confirmar y crea las reglas "Source: <nombre>" que falten (ACCOUNT_ID=<id>)'
  task reconcile_agents: :environment do
    account_id = ENV['ACCOUNT_ID'].presence || ENV['AUDITORIA_ACCOUNT_ID'].presence
    raise 'Pasa el account_id: rake auditoria:reconcile_agents ACCOUNT_ID=1' if account_id.blank?

    account = Account.find(account_id)
    raise "La cuenta #{account.id} no tiene el feature 'auditoria' activo" unless account.feature_enabled?('auditoria')

    result = Auditoria::AgentReconcilerService.new(account: account).call

    puts "Verificados: #{result[:confirmed].inspect}"
    puts "Reglas creadas: #{result[:rules_created].inspect}"
    if result[:orphan_rules].present?
      puts "ATENCION - reglas sin agente que coincida: #{result[:orphan_rules].inspect}"
    else
      puts 'Sin reglas huerfanas.'
    end
  end
end

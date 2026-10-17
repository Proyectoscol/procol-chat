# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :auditoria do
  # Tambien corre sola en cada boot del contenedor (ver docker/entrypoints/rails.sh)
  # cuando AUDITORIA_ACCOUNT_ID esta seteado.
  desc 'Prende el feature "auditoria" si falta y reconcilia agentes/reglas "Source: <nombre>" (ACCOUNT_ID=<id>)'
  task reconcile_agents: :environment do
    account_id = ENV['ACCOUNT_ID'].presence || ENV['AUDITORIA_ACCOUNT_ID'].presence
    raise 'Pasa el account_id: rake auditoria:reconcile_agents ACCOUNT_ID=1' if account_id.blank?

    account = Account.find(account_id)

    # with_lock: el entrypoint corre esta tarea en cada boot (web y sidekiq
    # bootean este mismo entrypoint), asi que puede llegar a correr dos veces
    # en paralelo en un redeploy - el lock serializa para que no se dupliquen
    # reglas de asignacion por una carrera entre ambos procesos.
    result = account.with_lock do
      account.enable_features!('auditoria') unless account.feature_enabled?('auditoria')
      Auditoria::AgentReconcilerService.new(account: account).call
    end

    puts "Verificados: #{result[:confirmed].inspect}"
    puts "Reglas creadas: #{result[:rules_created].inspect}"
    if result[:orphan_rules].present?
      puts "ATENCION - reglas sin agente que coincida: #{result[:orphan_rules].inspect}"
    else
      puts 'Sin reglas huerfanas.'
    end
  end

  desc 'Limpia el content visual (Source/type message/reply) y enlaza replies reales para mensajes existentes (ACCOUNT_ID=<id>)'
  task annotate_messages: :environment do
    account_id = ENV['ACCOUNT_ID'].presence || ENV['AUDITORIA_ACCOUNT_ID'].presence
    raise 'Pasa el account_id: rake auditoria:annotate_messages ACCOUNT_ID=1' if account_id.blank?

    account = Account.find(account_id)
    raise "La cuenta #{account.id} no tiene el feature 'auditoria' activo" unless account.feature_enabled?('auditoria')

    annotated = 0
    quoted = 0

    # broadcast: false -- ver Auditoria::MessageAnnotatorService. Sin esto,
    # miles de updates en una sola corrida inundan Sidekiq de jobs de
    # "message.updated" y saturan la CPU para un aviso en vivo que nadie
    # necesita en un backfill de mensajes historicos.
    account.messages.order(:id).find_each do |message|
      Auditoria::MessageAnnotatorService.new(message: message, broadcast: false).call
      next unless message.content_attributes.key?('auditoria_display_content')

      annotated += 1
      quoted += 1 if message.content_attributes['auditoria_quoted_text'].present?
    end

    puts "Mensajes anotados: #{annotated}"
    puts "Replies con cita estatica: #{quoted}"
  end
end
# rubocop:enable Metrics/BlockLength

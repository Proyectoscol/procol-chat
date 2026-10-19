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
      # captain_tasks viene "enabled: true" en config/features.yml, pero ese
      # default no aplica retroactivamente a cuentas ya existentes (solo a
      # cuentas creadas despues de que el flag se agrego) - sin esto, "Auditor
      # IA" queda bloqueado en silencio para esta cuenta.
      account.enable_features!('captain_tasks') unless account.feature_enabled?('captain_tasks')
      Auditoria::AiFieldConfig::DEFAULTS.each_with_index do |defaults, index|
        config = account.auditoria_ai_field_configs.find_or_initialize_by(field_order: index + 1)
        config.update!(defaults) unless config.persisted?
      end
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
    resolved = 0
    unresolved = 0

    # broadcast: false -- ver Auditoria::MessageAnnotatorService. Sin esto,
    # miles de updates en una sola corrida inundan Sidekiq de jobs de
    # "message.updated" y saturan la CPU para un aviso en vivo que nadie
    # necesita en un backfill de mensajes historicos.
    account.messages.order(:id).find_each do |message|
      Auditoria::MessageAnnotatorService.new(message: message, broadcast: false).call
      next unless message.content_attributes.key?('auditoria_display_content')

      annotated += 1
      quoted += 1 if message.content_attributes['auditoria_quoted_text'].present?
      message.content_attributes['auditoria_source_user_id'].present? ? resolved += 1 : unresolved += 1
    end

    multiple_advisors = account.conversations.tagged_with(
      Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE
    ).count

    puts "Mensajes anotados: #{annotated}"
    puts "Replies con cita estatica: #{quoted}"
    puts "Mensajes con asesor resuelto: #{resolved}"
    puts "Mensajes con Source sin agente coincidente: #{unresolved}" if unresolved.positive?
    puts "Conversaciones marcadas como multiple asesor: #{multiple_advisors}"
  end

  desc 'Crea los 5 campos de IA por defecto para Auditor IA si no existen (ACCOUNT_ID=<id>)'
  task seed_ai_field_configs: :environment do
    account_id = ENV['ACCOUNT_ID'].presence || ENV['AUDITORIA_ACCOUNT_ID'].presence
    raise 'Pasa el account_id: rake auditoria:seed_ai_field_configs ACCOUNT_ID=1' if account_id.blank?

    account = Account.find(account_id)

    created = 0
    Auditoria::AiFieldConfig::DEFAULTS.each_with_index do |defaults, index|
      config = account.auditoria_ai_field_configs.find_or_initialize_by(field_order: index + 1)
      next if config.persisted?

      config.update!(defaults)
      created += 1
    end

    puts "Campos creados: #{created}"
    puts "Total de campos en la cuenta: #{account.auditoria_ai_field_configs.count}"
  end
end
# rubocop:enable Metrics/BlockLength

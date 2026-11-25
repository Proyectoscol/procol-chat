# Siembra en Calendario::MessageTemplate los 2 textos nuevos del rediseño
# del bot de bienvenida (2026-11-25), para que queden editables desde
# Ajustes sin tocar codigo. Idempotente -- si la key ya existe activa, no
# hace nada.
#
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/seed_welcome_bot_message_templates.rb

account = Account.find(1)

TEMPLATES = [
  {
    key: 'bot_handoff_default',
    label: 'Bot bienvenida: entrega a agente (handoff)',
    body: 'Gracias por indicarnos esos datos. {{ agent_intro }}¿Hay algo más que debamos saber, ' \
          'o prefieres esperar nuestra respuesta?'
  },
  {
    key: 'bot_ginecologia_embarazo_rechazo',
    label: 'Bot bienvenida: rechazo por embarazo (ginecología)',
    body: 'Por este medio no atendemos pacientes en estado de embarazo para consultas de ginecología. ' \
          'Un asesor te contactará para orientarte.'
  }
].freeze

TEMPLATES.each do |t|
  if Calendario::MessageTemplate.for_key(t[:key]).where(account: account).active.exists?
    puts "#{t[:key]}: ya existe activa, no se toca"
    next
  end

  version = Calendario::MessageTemplate.next_version_for(account, t[:key])
  template = account.calendario_message_templates.create!(
    key: t[:key], label: t[:label], body: t[:body], version: version, status: 'draft'
  )
  template.activate!
  puts "#{t[:key]}: creada v#{version} y activada"
end

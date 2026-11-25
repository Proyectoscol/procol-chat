# Aplica en produccion los cambios de datos del rediseño del bot de
# bienvenida 2026-11-25 (el codigo ya se desplegó por separado):
#   1. Inserta los 2 pasos de la pregunta de embarazo en el flow "Triaje
#      general" (si no existen ya).
#   2. Setea el content_sid real de la plantilla bot_embarazo_ask (creada y
#      sometida a aprobacion -- ver create_embarazo_template.rb).
#
# Idempotente: si ya existen los pasos (mismo "if"/"ask"), no los duplica.
#
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/update_welcome_bot_prod.rb

CONTENT_SID = 'HXdd3c31a00c8ab3fd1b7b5a0efcc7f99a'.freeze

flow = Calendario::WelcomeBotFlow.find_by(match_type: 'default', priority: 0)
raise 'no se encontro el flow de triaje general' if flow.blank?

steps = flow.steps
existing_index = steps.find_index { |s| s['ask'].to_s.include?('embarazo') }

if existing_index
  steps[existing_index]['content_sid'] = CONTENT_SID
  flow.update!(steps: steps)
  puts "ya existia el paso de embarazo (indice #{existing_index}) -- content_sid actualizado"
else
  ask_index = steps.size
  notify_index = steps.size + 1
  steps << {
    'if' => { 'step' => 1, 'equals' => 'Ginecología' },
    'ask' => '¿La paciente está en estado de embarazo?',
    'type' => 'ask',
    'options' => %w[Sí No],
    'content_sid' => CONTENT_SID
  }
  steps << {
    'if' => { 'step' => ask_index, 'equals' => 'Sí' },
    'type' => 'notify',
    'ack_message_key' => 'bot_ginecologia_embarazo_rechazo',
    'ack_message' => 'Por este medio no atendemos pacientes en estado de embarazo para consultas de ' \
                      'ginecología. Un asesor te contactará para orientarte.'
  }
  flow.update!(steps: steps)
  puts "pasos de embarazo agregados en indices #{ask_index} y #{notify_index}"
end

puts "avisos de plantilla pendiente: #{flow.missing_template_warnings.inspect}"

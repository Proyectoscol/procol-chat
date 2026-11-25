# Completa las 2 plantillas de WhatsApp que faltaban en el flow "Triaje
# general" (pasos 4 y 5, ver fix de rediseño 2026-11-25) -- ambas sin
# variables, botones fijos.
#
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/create_remaining_bot_templates.rb

CHANNEL = Channel::TwilioSms.find(1)
API_CLIENT = Twilio::CsatTemplateApiClient.new(CHANNEL)

TEMPLATES = [
  {
    friendly_name: 'bot_cita_existente_opciones',
    body: '{{1}}',
    variables: { '1' => '¿Te refieres a tu cita del 2026-12-01 a las 08:00 AM con Dr. Corrales (Consulta)?' },
    buttons: ['Reagendar', 'Cancelar', 'Hablar con recepción']
  },
  {
    friendly_name: 'bot_lista_espera_opciones',
    body: '¿Quiere seguir en lista de espera para una cita posterior, o cancelarla definitivamente?',
    variables: {},
    buttons: ['Seguir en lista de espera', 'Cancelar definitivamente']
  }
].freeze

results = TEMPLATES.map do |template|
  request_body = {
    friendly_name: template[:friendly_name],
    language: 'es',
    variables: template[:variables],
    types: {
      'twilio/quick-reply' => {
        body: template[:body],
        actions: template[:buttons].map { |title| { id: title.parameterize, title: title } }
      }
    }
  }

  creation_response = API_CLIENT.create_template(request_body)
  unless creation_response.success? && creation_response['sid']
    puts "❌ #{template[:friendly_name]}: fallo la creacion -- #{creation_response.code} #{creation_response.body}"
    next
  end

  content_sid = creation_response['sid']
  approval_url = creation_response.dig('links', 'approval_create')
  approval_response = API_CLIENT.submit_for_approval(approval_url, template[:friendly_name], 'UTILITY')

  if approval_response.success?
    puts "✅ #{template[:friendly_name]} -- content_sid=#{content_sid} (sometida a aprobacion)"
  else
    puts "⚠️  #{template[:friendly_name]} -- content_sid=#{content_sid} creada PERO fallo aprobacion: #{approval_response.code} #{approval_response.body}"
  end
  { friendly_name: template[:friendly_name], content_sid: content_sid }
end

puts
puts results.compact.inspect

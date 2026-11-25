# Crea y somete a aprobacion de Meta la plantilla de WhatsApp para la
# pregunta de embarazo del flow "Triaje general" (rediseño 2026-11-25) --
# botones Sí/No, sin variables (pregunta fija, confirmada con el usuario).
#
# Corre UNA sola vez (cuenta real de Twilio, compartida entre local y
# producción). Despues de correr, revisar estado de aprobacion en
# Ajustes -> Entradas -> bandeja WhatsApp -> "Sync Templates", y cuando
# este aprobada, setear el content_sid en el paso del flow (ver
# add_embarazo_steps.rb / la fila correspondiente en producción).
#
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/create_embarazo_template.rb

CHANNEL = Channel::TwilioSms.find(1)
API_CLIENT = Twilio::CsatTemplateApiClient.new(CHANNEL)

request_body = {
  friendly_name: 'bot_embarazo_ask',
  language: 'es',
  variables: {},
  types: {
    'twilio/quick-reply' => {
      body: '¿La paciente está en estado de embarazo?',
      actions: [
        { id: 'si', title: 'Sí' },
        { id: 'no', title: 'No' }
      ]
    }
  }
}

creation_response = API_CLIENT.create_template(request_body)

unless creation_response.success? && creation_response['sid']
  puts "❌ fallo la creacion -- #{creation_response.code} #{creation_response.body}"
  exit 1
end

content_sid = creation_response['sid']
approval_url = creation_response.dig('links', 'approval_create')
approval_response = API_CLIENT.submit_for_approval(approval_url, 'bot_embarazo_ask', 'UTILITY')

if approval_response.success?
  puts "✅ bot_embarazo_ask -- content_sid=#{content_sid} (sometida a aprobacion, categoria UTILITY)"
else
  puts "⚠️  content_sid=#{content_sid} creada PERO fallo el sometimiento a aprobacion: " \
       "#{approval_response.code} #{approval_response.body}"
end

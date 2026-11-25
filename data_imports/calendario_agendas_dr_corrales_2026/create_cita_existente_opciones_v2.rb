# Reintento de bot_cita_existente_opciones -- la primera version (body
# "{{1}}" sin texto fijo alrededor) fue RECHAZADA por Meta en segundos: una
# plantilla de WhatsApp no puede tener como body solo una variable, necesita
# texto estatico real rodeandola. Esta version usa un body fijo que SIEMPRE
# aplica (no reusa el texto variable de la pregunta, que ya vive en el
# template "bot_cita_existente_ask" usado como ask_template del paso).
#
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/create_cita_existente_opciones_v2.rb

CHANNEL = Channel::TwilioSms.find(1)
API_CLIENT = Twilio::CsatTemplateApiClient.new(CHANNEL)

request_body = {
  friendly_name: 'bot_cita_existente_opciones_v2',
  language: 'es',
  variables: {},
  types: {
    'twilio/quick-reply' => {
      body: 'Por favor selecciona una opción:',
      actions: [
        { id: 'reagendar', title: 'Reagendar' },
        { id: 'cancelar', title: 'Cancelar' },
        { id: 'hablar-con-recepcion', title: 'Hablar con recepción' }
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
approval_response = API_CLIENT.submit_for_approval(approval_url, 'bot_cita_existente_opciones_v2', 'UTILITY')

if approval_response.success?
  puts "✅ bot_cita_existente_opciones_v2 -- content_sid=#{content_sid} (sometida a aprobacion)"
else
  puts "⚠️  content_sid=#{content_sid} creada PERO fallo el sometimiento: #{approval_response.code} #{approval_response.body}"
end

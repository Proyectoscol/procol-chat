# Envia un borrador de Cartera::PlantillaWhatsapp al Content API de Twilio
# y la somete a aprobacion de WhatsApp en el mismo paso (como en el flujo
# que documento el usuario en twiliocrearplantillas). A partir de aqui el
# estado real de aprobacion lo lee channel.content_templates - el espejo
# que mantiene Twilio::TemplateSyncService -, nunca duplicado aqui.
class Cartera::Plantillas::WhatsappSubmissionService
  class Error < StandardError; end

  pattr_initialize [:plantilla!]

  def call
    raise Error, "Esta plantilla ya fue enviada a Twilio (content_sid=#{plantilla.content_sid})." if plantilla.enviada?

    content_sid = crear_en_twilio
    solicitar_aprobacion
    plantilla.update!(content_sid: content_sid, estado: 'enviada')
    plantilla
  end

  private

  def crear_en_twilio
    response = api_client.create_template(cuerpo_creacion)
    raise Error, "Twilio rechazo la creacion de la plantilla: #{response.code} - #{response.body}" unless response.success? && response['sid']

    @approval_url = response.dig('links', 'approval_create')
    response['sid']
  end

  def solicitar_aprobacion
    raise Error, 'Twilio no devolvio la URL de aprobacion para esta plantilla.' if @approval_url.blank?

    response = api_client.submit_for_approval(@approval_url, plantilla.nombre, plantilla.categoria.upcase)
    raise Error, "Twilio rechazo la solicitud de aprobacion: #{response.code} - #{response.body}" unless response.success?
  end

  def cuerpo_creacion
    {
      friendly_name: plantilla.nombre,
      language: plantilla.idioma,
      variables: ejemplos_de_variables,
      types: { 'twilio/text' => { body: plantilla.cuerpo } }
    }
  end

  # Valores de ejemplo para que el revisor de Meta vea el mensaje con datos
  # reales en vez de {{1}}, {{2}}... - no afecta el envio real, que usa
  # Cartera::Campanas::VariableResolver contra cada cliente.
  EJEMPLOS = {
    'nombre_cliente' => 'Juan Pérez',
    'saldo_abierto' => '$450.000',
    'dias_vencido' => '32',
    'tramo' => '31-60 días',
    'numero_factura' => 'FE-1023',
    'fecha_vencimiento' => '15/11/2026'
  }.freeze

  def ejemplos_de_variables
    Hash(plantilla.variables).transform_values { |nombre_semantico| EJEMPLOS[nombre_semantico] || '' }
  end

  def api_client
    @api_client ||= Twilio::CsatTemplateApiClient.new(canal_whatsapp)
  end

  def canal_whatsapp
    Channel::TwilioSms.whatsapp_for_account(plantilla.account_id) ||
      raise(Error, 'No hay un canal de WhatsApp (Twilio) configurado en esta cuenta.')
  end
end

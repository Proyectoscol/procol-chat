# Ejecuta el envio (WhatsApp) de un cartera_envios "programado": encuentra o
# crea la conversacion de Chatwoot para el cliente y construye un mensaje de
# plantilla. El pipeline existente de Chatwoot (Message after_create ->
# SendReplyJob -> Twilio::SendOnTwilioService) hace la llamada real a
# Twilio de forma asincrona - no se reimplementa aqui.
#
# El resultado (entregado/leido/fallido) se refleja despues en
# cartera_envios via Cartera::Campanas::ActualizarEstadoEnviosJob, que lee
# el status del Message (actualizado por el webhook real de Twilio via
# Twilio::DeliveryStatusService).
#
# Si envio.modo_prueba? (Cartera::Campanas::PruebaService), nada de esto
# llega a Twilio: la conversacion se crea contra la bandeja de pruebas
# (Channel::Api, ver InboxPruebasResolver) y SendReplyJob no hace ninguna
# llamada externa real para ese tipo de canal.
class Cartera::Campanas::EnvioWhatsappService
  pattr_initialize [:envio!]

  def call
    return unless envio.estado == 'programado' && envio.canal == 'whatsapp'

    plantilla = plantilla_whatsapp
    raise "No hay Cartera::PlantillaWhatsapp local para content_sid=#{content_sid} - no se pueden resolver sus variables." if plantilla.nil?

    contact_inbox = encontrar_o_crear_contact_inbox
    conversacion = encontrar_o_crear_conversacion(contact_inbox)
    mensaje = construir_mensaje(conversacion, plantilla)
    mensaje.save!
    envio.update!(message_id: mensaje.id, estado: 'enviado')
  end

  private

  def cliente
    @cliente ||= envio.cliente
  end

  def campana
    @campana ||= envio.campana
  end

  def regla
    @regla ||= envio.campana_regla
  end

  def content_sid
    regla.plantilla_whatsapp_content_sid
  end

  def inbox
    @inbox ||= if envio.modo_prueba?
                 Cartera::Campanas::InboxPruebasResolver.new(account: campana.account).resolver!
               else
                 campana.inbox_whatsapp || raise('La campana activa no tiene un inbox de WhatsApp configurado.')
               end
  end

  def plantilla_whatsapp
    @plantilla_whatsapp ||= campana.account.cartera_plantillas_whatsapp.find_by(content_sid: content_sid)
  end

  def template_mirror
    templates = Channel::TwilioSms.whatsapp_for_account(campana.account_id)&.content_templates&.dig('templates')
    @template_mirror ||= templates&.find { |t| t['content_sid'] == content_sid }
  end

  def encontrar_o_crear_contact_inbox
    ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: { name: cliente.nombre, phone_number: telefono_e164, email: cliente.email }
    ).perform
  end

  def telefono_e164
    Cartera::IndicativoTelefonico.formatear_e164(cliente.telefono, cliente.sucursal) ||
      raise("No se pudo determinar el telefono E.164 del cliente #{cliente.id}.")
  end

  def encontrar_o_crear_conversacion(contact_inbox)
    contact_inbox.conversations.where.not(status: :resolved).first || crear_conversacion(contact_inbox)
  end

  def crear_conversacion(contact_inbox)
    campana.account.conversations.create!(
      inbox_id: inbox.id, contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id
    )
  end

  # En modo prueba el mensaje es texto plano, sin la maquinaria de plantilla
  # de Twilio (content_sid, template_params): la bandeja de pruebas es un
  # Channel::Api generico, no entiende plantillas de WhatsApp - lo unico que
  # se esta probando aqui es la elegibilidad y la conversacion con el
  # Agente IA, no la entrega real.
  def construir_mensaje(conversacion, plantilla)
    variables = Cartera::Campanas::VariableResolver.new(envio: envio).resolve_todas(plantilla.variables)
    contenido = contenido_legible(plantilla.cuerpo, variables)

    if envio.modo_prueba?
      conversacion.messages.build(
        account: campana.account, inbox: inbox, sender: campana.captain_assistant,
        message_type: :outgoing, content: contenido
      )
    else
      conversacion.messages.build(
        account: campana.account, inbox: inbox, sender: campana.captain_assistant,
        message_type: :template, content: contenido,
        additional_attributes: { 'template_params' => template_params(plantilla, variables) }
      )
    end
  end

  def template_params(plantilla, variables)
    {
      'name' => template_mirror&.[]('friendly_name') || plantilla.nombre,
      'language' => template_mirror&.[]('language') || plantilla.idioma,
      'processed_params' => variables
    }
  end

  def contenido_legible(cuerpo, variables)
    variables.reduce(cuerpo) { |texto, (numero, valor)| texto.gsub("{{#{numero}}}", valor.to_s) }
  end
end

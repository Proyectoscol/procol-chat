# Ejecuta el envio real (correo) de un cartera_envios "programado": misma
# arquitectura que Cartera::Campanas::EnvioWhatsappService (ver ese
# archivo) pero para Channel::Email - encuentra o crea la conversacion y
# construye el mensaje; el pipeline existente de Chatwoot (Message
# after_create -> SendReplyJob -> Email::SendOnEmailService ->
# ConversationReplyMailer) hace el envio real de forma asincrona.
#
# message.content se renderiza con ChatwootMarkdownRenderer (ver
# app/views/mailers/conversation_reply_mailer/*.erb), que permite HTML
# embebido - por eso Cartera::PlantillaEmail#cuerpo_html puede escribirse
# con etiquetas simples (<p>, <strong>, <br>) y llega intacto al correo.
#
# Si envio.modo_prueba? (Cartera::Campanas::PruebaService), la conversacion
# se crea contra la bandeja de pruebas (Channel::Api, ver
# InboxPruebasResolver) y no sale ningun correo real.
class Cartera::Campanas::EnvioEmailService
  pattr_initialize [:envio!]

  def call
    return unless envio.estado == 'programado' && envio.canal == 'email'

    plantilla = plantilla_email
    raise "La regla #{regla.id} no tiene una Cartera::PlantillaEmail asociada." if plantilla.nil?

    contact_inbox = encontrar_o_crear_contact_inbox
    conversacion = encontrar_o_crear_conversacion(contact_inbox, plantilla)
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

  def inbox
    @inbox ||= if envio.modo_prueba?
                 Cartera::Campanas::InboxPruebasResolver.new(account: campana.account).resolver!
               else
                 campana.inbox_email || raise('La campana activa no tiene un inbox de correo configurado.')
               end
  end

  def plantilla_email
    @plantilla_email ||= Cartera::PlantillaEmail.find_by(id: regla.plantilla_email_id)
  end

  def encontrar_o_crear_contact_inbox
    ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: { name: cliente.nombre, email: cliente.email, phone_number: telefono_e164 }
    ).perform
  end

  # Contact#phone_number exige formato E.164 - un telefono fijo colombiano
  # crudo (ej. "6011234567") lo rompe aunque el canal sea correo. Mismo
  # formateador que EnvioWhatsappService; nil cuando no se puede formatear
  # con confianza es un valor valido (Contact#phone_number es opcional).
  def telefono_e164
    Cartera::IndicativoTelefonico.formatear_e164(cliente.telefono, cliente.sucursal)
  end

  def encontrar_o_crear_conversacion(contact_inbox, plantilla)
    contact_inbox.conversations.where.not(status: :resolved).first || crear_conversacion(contact_inbox, plantilla)
  end

  def crear_conversacion(contact_inbox, plantilla)
    campana.account.conversations.create!(
      inbox_id: inbox.id, contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id,
      additional_attributes: { 'mail_subject' => plantilla.asunto }
    )
  end

  def construir_mensaje(conversacion, plantilla)
    variables = Cartera::Campanas::VariableResolver.new(envio: envio).resolve_todas(plantilla.variables)

    conversacion.messages.build(
      account: campana.account, inbox: inbox, sender: campana.captain_assistant,
      message_type: :outgoing,
      content: contenido_legible(plantilla.cuerpo_html, variables)
    )
  end

  def contenido_legible(cuerpo, variables)
    variables.reduce(cuerpo) { |texto, (numero, valor)| texto.gsub("{{#{numero}}}", valor.to_s) }
  end
end

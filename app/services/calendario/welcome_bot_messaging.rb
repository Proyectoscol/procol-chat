# Helpers de envio compartidos entre Calendario::WelcomeBotFlowRunner (motor
# generico de preguntas/pasos) y Calendario::WelcomeBotAppointmentActions
# (acciones del flujo de "cita existente") -- requiere que quien lo incluya
# responda a conversation/account/inbox.
module Calendario::WelcomeBotMessaging
  private

  def step_body(step)
    body = step['ask'].to_s
    options = step['buttons'] || step['options']
    body += "\n\n#{Array(options).join("\n")}" if options.present?
    body
  end

  # Manda el quick-reply real de WhatsApp (content_sid ya creado en Twilio,
  # ver Twilio::CsatTemplateApiClient) como respuesta de sesion -- no
  # requiere aprobacion de Meta porque siempre es una respuesta a un mensaje
  # entrante del paciente, no un mensaje que inicia conversacion. Mismo
  # patron que Csat::SurveyService#send_twilio_whatsapp_template_survey:
  # mensaje sin guardar -> se manda por fuera -> se persiste con source_id
  # ya puesto para que SendReplyJob no lo reenvie como texto plano.
  def send_whatsapp_buttons(step)
    message = conversation.messages.build(
      account: account, inbox: inbox, message_type: :outgoing, content: step_body(step)
    )
    result = Twilio::SendOnTwilioService.new(message: message).send_csat_template_message(
      phone_number: conversation.contact_inbox.source_id, content_sid: step['content_sid']
    )
    message.source_id = result[:message_id] if result[:success] && result[:message_id].present?
    message.save!
  end

  # Paso de texto libre -- mensaje real normal, el pipeline estandar
  # (SendReplyJob) lo entrega por Twilio igual que una respuesta tipeada por
  # un agente.
  def send_text_question(step)
    conversation.messages.create!(
      account: account, inbox: inbox, message_type: :outgoing, content: step_body(step)
    )
  end

  # Usada solo para notas internas -- nunca llega al paciente.
  def create_private_note(body)
    conversation.messages.create!(
      account: account, inbox: inbox, private: true, message_type: :outgoing, content: body
    )
  end

  def normalize(text)
    Calendario::WelcomeBotFlow.normalize(text)
  end

  # Si el paso (o el caller) referencia una key de Calendario::MessageTemplate,
  # su version activa tiene prioridad sobre el texto literal -- la
  # biblioteca es la fuente de verdad para todo texto editable hacia el
  # paciente, no solo las acciones de cita (ver Calendario::WelcomeBotAppointmentActions,
  # que usaba una copia de este mismo metodo antes de moverlo aqui).
  def resolved_text(step, key_field, literal_field, default)
    key = step[key_field]
    library_text = key.present? ? Calendario::MessageTemplate.active_body(account, key) : nil
    library_text.presence || step[literal_field].presence || default
  end

  def render_liquid(template, locals)
    Liquid::Template.parse(template).render!(locals)
  rescue Liquid::Error
    template
  end

  # A diferencia de la auto-asignacion generica de Chatwoot, NUNCA filtra por
  # agente "online" -- un paciente que escribe fuera de horario debe quedar
  # igual de asignado (ver Calendario::WelcomeBotAssignmentService).
  def assign_available_agent
    Calendario::WelcomeBotAssignmentService.new(conversation: conversation).perform
  end
end

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
    # content_variables solo cuando el paso lo marca explicitamente
    # ('dynamic_body_variable' => true, ver Calendario::WelcomeBotAppointmentActions
    # #lookup_confirmation_step) -- esa es la UNICA plantilla pensada para
    # llevar un placeholder real ("{{1}}", la confirmacion de cita con
    # fecha/hora via Liquid). Los demas pasos (menu, especialidad, tipo de
    # pago, embarazo) tienen body FIJO en su plantilla -- mandarles una
    # variable que no esperan arriesgaria que Twilio rechace el envio.
    content_variables = step['dynamic_body_variable'] ? { '1' => step['ask'] } : {}
    message = conversation.messages.build(
      account: account, inbox: inbox, message_type: :outgoing,
      content: rendered_whatsapp_body(step, content_variables)
    )
    result = Twilio::SendOnTwilioService.new(message: message).send_csat_template_message(
      phone_number: conversation.contact_inbox.source_id, content_sid: step['content_sid'],
      content_variables: content_variables
    )
    message.source_id = result[:message_id] if result[:success] && result[:message_id].present?
    message.save!
  end

  # Bug real en produccion 2026-11-26 (conversacion #323): el mensaje que se
  # veia en Chatwoot (la pregunta completa con fecha/hora de la cita) NUNCA
  # llego a WhatsApp -- la plantilla aprobada de ese content_sid tiene body
  # FIJO ("Por favor selecciona una opcion:"), sin ningun "{{1}}" real donde
  # inyectar la pregunta dinamica, asi que Twilio simplemente ignoraba
  # content_variables y mandaba el texto generico. Guardar `step_body(step)`
  # a ciegas en Chatwoot le mostraba al staff una conversacion que no
  # reflejaba lo que el paciente de verdad recibio -- imposible validar nada
  # asi. Ahora se resuelve el body REAL de la plantilla aprobada (con las
  # variables ya sustituidas) y eso es lo unico que se guarda como contenido
  # del mensaje; si la plantilla no tiene placeholder para una variable,
  # Chatwoot muestra el mismo texto fijo que de verdad llego, nunca una
  # version inventada mas completa.
  def rendered_whatsapp_body(step, content_variables)
    template = inbox.channel.content_templates['templates']&.find { |t| t['content_sid'] == step['content_sid'] }
    body = template&.dig('body').presence
    return step_body(step) if body.blank?

    content_variables.reduce(body) { |text, (key, value)| text.gsub("{{#{key}}}", value.to_s) }
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

  OUT_OF_OFFICE_NOTICE_KEY = 'bot_out_of_office_notice'.freeze
  DEFAULT_OUT_OF_OFFICE_NOTICE =
    'Actualmente estamos fuera de nuestro horario de atención. Te atenderemos tan pronto regresemos.'.freeze
  DEFAULT_IN_OFFICE_NOTICE = 'En breve, nuestro equipo de recepción atenderá tu solicitud.'.freeze

  # Bug real en produccion 2026-11-25 (10pm): el texto fijo "En breve..."
  # miente cuando se manda fuera de horario laboral -- usar como
  # `{{ office_status_notice }}` en cualquier plantilla editable que haga
  # esa promesa, para que se ajuste sola segun el horario real (incluye
  # festivos colombianos y excepciones, ver Calendario::BusinessHours).
  def office_status_notice
    return DEFAULT_IN_OFFICE_NOTICE if Calendario::BusinessHours.new(inbox: inbox).open_at?

    Calendario::MessageTemplate.active_body(account, OUT_OF_OFFICE_NOTICE_KEY).presence || DEFAULT_OUT_OF_OFFICE_NOTICE
  end

  # A diferencia de la auto-asignacion generica de Chatwoot, NUNCA filtra por
  # agente "online" -- un paciente que escribe fuera de horario debe quedar
  # igual de asignado (ver Calendario::WelcomeBotAssignmentService).
  def assign_available_agent
    Calendario::WelcomeBotAssignmentService.new(conversation: conversation).perform
  end
end

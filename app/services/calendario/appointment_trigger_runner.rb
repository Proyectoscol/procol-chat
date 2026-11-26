# Envia la plantilla de un Calendario::AppointmentEventTrigger para una cita
# puntual. Deliberadamente NO hereda de ActionService/AutomationRules::ActionService
# (ver addendum del 2026-10-29 al eng-review): esos dos quedan atados a
# @conversation via Messages::MessageBuilder y no tienen forma de elegir
# canal/plantilla explicitos. Este runner sigue el patron de
# Whatsapp::OneoffCampaignService en cambio: inbox + contacto, sin conversacion.
#
# trigger.test_mode: pedido explicito del usuario antes de pasar a produccion
# ("quiero primero hacer envios de notas privadas no de mensajes reales,
# para ver como esta funcionando el envio") -- en vez de llamar a
# channel.send_template (que le pega directo a la API de WhatsApp sin crear
# ningun registro local, ver Whatsapp::Providers::WhatsappCloudService#send_template),
# crea una nota privada en la conversacion con el texto que se habria
# enviado. Nunca sale un mensaje real mientras test_mode este activo.
class Calendario::AppointmentTriggerRunner
  # defer_attempt: cuantas veces ya se aplazo este mismo envio por choque de
  # sesion de bot activa (ver Calendario::AppointmentReminderBotSession) --
  # 0 en el primer intento, lo incrementa AppointmentTriggerReminderJob cada
  # vez que se reencola.
  pattr_initialize [:trigger!, :appointment!, { defer_attempt: 0 }]

  def perform
    return :already_fired if already_fired?
    return :inactive unless trigger.active? && appointment_still_applies?
    return :no_phone if appointment.contact.phone_number.blank?
    return :deferred if deferred_for_session_conflict?

    trigger.test_mode? ? create_private_note : send_template_message
    record_firing!
    :sent
  end

  private

  def deferred_for_session_conflict?
    !trigger.test_mode? && bot_session.defer?(find_or_create_conversation)
  end

  delegate :inbox, to: :trigger
  delegate :channel, to: :inbox
  delegate :contact, :account, to: :appointment

  def already_fired?
    Calendario::AppointmentTriggerFiring.exists?(trigger_id: trigger.id, appointment_id: appointment.id)
  end

  # Para before_start: si ya se confirmo/atendio/cancelo/no-show desde que se
  # encolo el recordatorio, ya no aplica -- esto es lo que detiene la
  # escalera de recordatorios sin necesitar cancelar el ActiveJob encolado
  # (no hay forma nativa de cancelarlo en este stack; el guard en el momento
  # de ejecutar es el patron ya usado en el resto del codebase).
  #
  # Para on_status_change con delay_minutes>0: mismo problema -- si el
  # estado volvio a cambiar durante la espera (ej. marcada "atendida" por
  # error y corregida a "no_show" antes de que corriera el job demorado),
  # ya no tiene sentido mandar el mensaje del estado viejo.
  def appointment_still_applies?
    return appointment.pending? || appointment.confirmed? if trigger.before_start?
    return appointment.status == trigger.target_status if trigger.on_status_change?

    true
  end

  def bot_session
    @bot_session ||= Calendario::AppointmentReminderBotSession.new(
      trigger: trigger, appointment: appointment, defer_attempt: defer_attempt
    )
  end

  # IMPORTANTE: el send real (Meta) usa trigger.template_params crudo, nunca
  # effective_template_params -- la key de biblioteca solo sustituye el body
  # libre (string) de la nota de prueba/preview; si se mezclara con el send
  # real, pisaria los componentes estructurados (header/body con parametros
  # posicionales) que Whatsapp::TemplateProcessorService espera como Hash,
  # rompiendo cualquier plantilla aprobada con variables.
  def processed_template_params(params = trigger.template_params)
    Calendario::AppointmentLiquidTemplateProcessorService.new(appointment: appointment, inbox: inbox)
                                                         .process_template_params(params)
  end

  def preview_template_params
    processed_template_params(trigger.effective_template_params)
  end

  def send_template_message
    return send_twilio_template_message if twilio_whatsapp_with_content_sid?

    processed = processed_template_params
    return if processed.blank?

    processor = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: processed)
    name, namespace, lang_code, parameters = processor.call
    return if name.blank?

    channel.send_template(contact.phone_number, {
                            name: name, namespace: namespace, lang_code: lang_code, parameters: parameters
                          }, nil)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  # Bandejas Twilio no tienen catalogo de plantillas de Meta -- el trigger
  # elige una plantilla real de Twilio (content_sid, ya sincronizada via
  # Twilio::TemplateSyncService) en vez de name/namespace/lang_code. Mismo
  # mecanismo que ya usa Calendario::WelcomeBotFlowRunner#send_whatsapp_buttons
  # para los botones del bot de bienvenida.
  def twilio_whatsapp_with_content_sid?
    inbox.twilio_whatsapp? && trigger.template_params['content_sid'].present?
  end

  def send_twilio_template_message
    conversation = find_or_create_conversation
    return if conversation.blank?

    content_variables = resolve_content_variables
    if incomplete_variable_mapping?(content_variables)
      warn_incomplete_variable_mapping(conversation, content_variables)
      return
    end

    if bot_session.interactive?
      bot_session.start!(conversation)
    else
      Calendario::WelcomeBotExemption.new(conversation: conversation).apply!
    end

    message = build_twilio_message(conversation)
    # BUG REAL encontrado 2026-11-26: contact.phone_number no lleva el
    # prefijo "whatsapp:" -- Twilio lo rechaza con error 21910 ("Invalid
    # From and To pair. From and To should be of the same channel") porque
    # el messaging_service_sid configurado es de WhatsApp. El envio con
    # plantilla fallaba SIEMPRE (en los 8 disparadores activos), pero el
    # registro del mensaje ya quedaba creado -- el pipeline generico de
    # Chatwoot (Message#send_reply, disparado porque source_id seguia nil
    # tras el fallo) lo reenviaba como texto plano con el preview roto
    # ("Cita confirmada, 1"), que SI llegaba al paciente. conversation.contact_inbox.source_id
    # ya trae el prefijo correcto -- mismo patron que
    # Calendario::WelcomeBotMessaging#send_whatsapp_buttons, que nunca tuvo este bug.
    result = Twilio::SendOnTwilioService.new(message: message).send_csat_template_message(
      phone_number: conversation.contact_inbox.source_id, content_sid: trigger.template_params['content_sid'],
      content_variables: content_variables
    )
    apply_send_result(message, result)
  end

  # Red de seguridad: si al disparador le falta mapear alguna variable del
  # body de la plantilla (ej. guardado por script, o editado fuera del
  # formulario que SI valida esto), Twilio no rechaza el envio -- renderiza
  # el placeholder crudo ("1", "2"...) al paciente. Hallazgo real 2026-11-26:
  # asi llego "Cita confirmada, 1" a un paciente. Mejor no enviar nada y
  # avisar internamente que arreglar la configuracion.
  def expected_variable_keys
    template = channel.content_templates&.dig('templates')&.find do |t|
      t['content_sid'] == trigger.template_params['content_sid']
    end
    template&.dig('body').to_s.scan(/{{\s*(\d+)\s*}}/).flatten.uniq
  end

  def incomplete_variable_mapping?(content_variables)
    expected_variable_keys.any? { |key| content_variables[key].blank? }
  end

  def warn_incomplete_variable_mapping(conversation, content_variables)
    missing = expected_variable_keys.reject { |key| content_variables[key].present? }
    text = "⚠️ El disparador \"#{trigger.template_params['friendly_name']}\" no se envió: " \
           "faltan variables sin mapear (#{missing.join(', ')}). Revisa Ajustes → Mensajería → " \
           'Notificaciones para este disparador.'
    conversation.messages.create!(
      account: account, inbox: inbox, sender: Current.user, private: true,
      message_type: :outgoing, content: text
    )
    ChatwootExceptionTracker.new(
      StandardError.new("AppointmentEventTrigger##{trigger.id} variable_mapping incompleto " \
                        "para content_sid=#{trigger.template_params['content_sid']}"),
      account: account
    ).capture_exception
  end

  def build_twilio_message(conversation)
    conversation.messages.build(
      account: account, inbox: inbox, message_type: :outgoing,
      content: preview_text.presence || trigger.template_params['friendly_name'].to_s,
      content_attributes: { skip_send_reply: true }
    )
  end

  def apply_send_result(message, result)
    message.source_id = result[:message_id] if result[:success] && result[:message_id].present?
    message.status = :failed unless result[:success]
    message.save!
  end

  # El mapeo { "1" => "appointment.date", "2" => "contact.name", ... } se
  # configura en el formulario del trigger (ver AppointmentEventTriggerFormModal.vue)
  # -- cada valor es una expresion Liquid resuelta contra los mismos drops
  # que usa processed_template_params.
  def resolve_content_variables
    mapping = trigger.template_params['variable_mapping'] || {}
    mapping.transform_values { |expression| render_liquid_expression(expression) }
  end

  def render_liquid_expression(expression)
    Liquid::Template.parse("{{ #{expression} }}").render!(
      'contact' => ContactDrop.new(contact), 'appointment' => Calendario::AppointmentDrop.new(appointment),
      'inbox' => InboxDrop.new(inbox), 'account' => AccountDrop.new(account)
    )
  rescue Liquid::Error
    ''
  end

  def create_private_note
    text = preview_text
    return if text.blank?

    conversation = find_or_create_conversation
    return if conversation.blank?

    # NUNCA tocar estado real de la conversacion en test_mode (ni asignar
    # agente ni marcar skip_welcome_bot) -- hallazgo de Codex 2026-11-26: el
    # proposito entero de test_mode es "nunca sale un mensaje real" (ver
    # comentario de clase); un admin probando un disparador no deberia
    # asignar de verdad a un agente ni exentar permanentemente una
    # conversacion real solo por una corrida de prueba.

    conversation.messages.create!(
      account: account, inbox: inbox, sender: Current.user, private: true,
      message_type: :outgoing,
      content: "[PRUEBA -- este disparador esta en modo de prueba, nunca se envio un mensaje real]\n\n#{text}"
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  # El mismo texto que se habria enviado por WhatsApp, pero legible para el
  # personal -- header/body/footer de processed_params en texto plano en vez
  # de la forma de "componentes" que espera la API de Meta (eso solo le
  # sirve al provider real, no a una persona leyendo la nota).
  def preview_text
    params = preview_template_params&.dig('processed_params')
    return if params.blank?

    sections = %w[header body footer].filter_map do |section|
      values = params[section]
      next if values.blank?

      values.is_a?(Hash) ? values.values.compact.join(' ') : values.to_s
    end
    sections.join("\n\n").presence
  end

  # Mismo criterio de seleccion que Twilio::IncomingMessageService#set_conversation
  # -- hallazgo real de Codex 2026-11-26: un `find_by` sin order (como habia
  # antes) puede devolver una conversacion distinta a la que Twilio reutiliza
  # para la respuesta REAL del paciente si algun dia existe mas de una
  # conversacion para el mismo contact_inbox (hoy, en produccion,
  # lock_to_single_conversation=true y ningun contact_inbox tiene mas de una
  # -- verificado -- pero el selector debe coincidir siempre, no solo hoy).
  def find_or_create_conversation
    contact_inbox = contact.contact_inboxes.find_by(inbox_id: inbox.id) || ContactInboxBuilder.new(
      contact: contact, inbox: inbox
    ).perform
    return if contact_inbox.blank?

    existing = if inbox.lock_to_single_conversation
                 contact_inbox.conversations.last
               else
                 contact_inbox.conversations.where.not(status: :resolved).last
               end

    existing || Conversation.create!(
      account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox
    )
  end

  def record_firing!
    Calendario::AppointmentTriggerFiring.create!(trigger: trigger, appointment: appointment, fired_at: Time.current)
  end
end

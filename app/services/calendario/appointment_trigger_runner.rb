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
  # Tolerancia para el guard de "job viejo de antes de un reagendado" (ver
  # #stale_before_start_run?) -- margen chico para no rechazar por latencia
  # normal de cola, pero suficiente para detectar un job que quedo apuntando
  # a una hora que ya no es la real.
  STALE_BEFORE_START_TOLERANCE = 2.minutes

  # defer_attempt: cuantas veces ya se aplazo este mismo envio por choque de
  # sesion de bot activa (ver Calendario::AppointmentReminderBotSession) --
  # 0 en el primer intento, lo incrementa AppointmentTriggerReminderJob cada
  # vez que se reencola.
  #
  # occurrence_token: solo lo pasa Calendario::Appointment#run_on_status_change_triggers
  # para el camino demorado -- ver comentario ahi y en #resolved_occurrence_token.
  pattr_initialize [:trigger!, :appointment!, { defer_attempt: 0 }, { occurrence_token: nil }]

  # Bug real encontrado en auditoria con Codex 2026-11-27 (hallazgos #3 y #4):
  # antes, el orden era "chequear ya_se_envio -> enviar -> grabar ya_se_envio",
  # lo cual (a) marcaba como "enviado" un intento que en realidad fallo en
  # Twilio (bloqueando para siempre cualquier reintento futuro de esa misma
  # ocurrencia), y (b) no protegia contra dos workers corriendo el mismo job
  # en paralelo (ambos pasaban el chequeo antes de que ninguno grabara nada).
  # Ahora la fila de "ya_se_envio" se RESERVA primero (atomico via el indice
  # unico de la base de datos: solo uno de dos workers concurrentes logra
  # crearla), y si el envio real despues falla, se borra la reserva para que
  # un reintento futuro si pueda volver a intentarlo.
  def perform
    blocked = blocking_status
    return blocked if blocked

    firing = reserve_firing!
    return :already_fired if firing.blank?

    # Bug real #5 de la auditoria (parte 2): entre el chequeo de arriba y
    # este punto pasan varios pasos (reservar la fila, resolver variables,
    # buscar/crear la conversacion) -- si justo en ese hueco alguien cancelo
    # la cita desde otro lado (UI, otro mensaje), sin este re-chequeo se
    # mandaria igual un recordatorio "confirma tu cita" contradiciendo el
    # mensaje de cancelacion que ya salio. appointment.reload trae el estado
    # mas fresco posible justo antes de disparar.
    appointment.reload
    unless appointment_still_applies?
      firing.destroy!
      return :inactive
    end

    success = dispatch!
    firing.destroy! unless success
    success ? :sent : :send_failed
  end

  private

  def blocking_status
    return :inactive unless trigger.active? && appointment_still_applies?
    return :stale if stale_before_start_run?
    return :no_phone if appointment.contact.phone_number.blank?
    return :deferred if deferred_for_session_conflict?

    nil
  end

  def dispatch!
    trigger.test_mode? ? create_private_note.present? : send_template_message
  end

  def deferred_for_session_conflict?
    !trigger.test_mode? && bot_session.defer?(find_or_create_conversation)
  end

  delegate :inbox, to: :trigger
  delegate :channel, to: :inbox
  delegate :contact, :account, to: :appointment

  def reserve_firing!
    Calendario::AppointmentTriggerFiring.create!(
      trigger: trigger, appointment: appointment, occurrence_token: resolved_occurrence_token, fired_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  # Distingue cada OCURRENCIA real del evento, no solo el par trigger+cita --
  # bug real #2 de la auditoria: con una llave permanente, un segundo
  # reagendado o un confirmada->pendiente->confirmada nunca volvian a
  # notificar porque la fila vieja ya "consumia" la llave para siempre.
  #
  # before_start: la hora actual de la cita -- un reagendado a una hora
  # distinta es una ocurrencia nueva (el job viejo, para la hora anterior,
  # ademas queda bloqueado por #stale_before_start_run? antes de llegar aca).
  # on_reschedule: reschedules_count ya es un contador que Calendario::Appointment
  # incrementa en cada reagendado (ver #log_reschedule), perfecto como version.
  # on_status_change: el occurrence_token explicito (capturado al encolar,
  # ver Calendario::Appointment#run_on_status_change_triggers) para el camino
  # demorado, o el ultimo audit_log de status_changed para el inmediato.
  # on_create: siempre la misma ocurrencia (una cita solo se crea una vez).
  def resolved_occurrence_token
    return occurrence_token if occurrence_token.present?

    case trigger.trigger_kind
    when 'before_start' then appointment.starts_at.to_i.to_s
    when 'on_reschedule' then appointment.reschedules_count.to_s
    when 'on_status_change' then appointment.status_change_occurrence_token
    else ''
    end
  end

  # Bug real #1 de la auditoria: reagendar una cita encola un job NUEVO para
  # el antes-de-la-cita correcto, pero no hay forma de cancelar el job VIEJO
  # ya encolado para la hora anterior -- si corre de todas formas, antes
  # solo chequeaba el ESTADO de la cita (seguia pendiente/confirmada), nunca
  # si la hora para la que fue programado seguia siendo la real. Resultado:
  # el job viejo enviaba "tu cita es en 1 hora" con la hora VIEJA, en el
  # momento equivocado, y encima bloqueaba (via la llave de ya_se_envio) el
  # job nuevo y correcto que si tenia la hora buena.
  def stale_before_start_run?
    return false unless trigger.before_start?
    return true if appointment.starts_at <= Time.current

    expected_fire_at = appointment.starts_at - trigger.offset_minutes.minutes
    expected_fire_at > STALE_BEFORE_START_TOLERANCE.from_now
  end

  # Para before_start: antes de hoy, "pendiente o confirmada" bastaba para
  # seguir aplicando -- pero un recordatorio INTERACTIVO (con botones,
  # pensado para pedir "confirma tu asistencia") no tiene sentido repetirlo
  # una vez el paciente YA confirmo (bug real #5 de la auditoria: el
  # comentario de este metodo decia explicitamente que debia detenerse al
  # confirmar, pero el codigo seguia permitiendolo). Un before_start NO
  # interactivo (ej. las recomendaciones de preparacion, que no piden nada)
  # si debe seguir aplicando mientras no este cancelada/atendida/no-show,
  # haya confirmado o no -- no es una pregunta, es informativo.
  #
  # Para on_status_change con delay_minutes>0: si el estado volvio a cambiar
  # durante la espera (ej. marcada "atendida" por error y corregida a
  # "no_show" antes de que corriera el job demorado), ya no tiene sentido
  # mandar el mensaje del estado viejo.
  def appointment_still_applies?
    return before_start_still_applies? if trigger.before_start?
    return appointment.status == trigger.target_status if trigger.on_status_change?

    true
  end

  def before_start_still_applies?
    return false unless appointment.pending? || appointment.confirmed?
    return appointment.pending? if bot_session.interactive?

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
    return false if processed.blank?

    processor = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: processed)
    name, namespace, lang_code, parameters = processor.call
    return false if name.blank?

    channel.send_template(contact.phone_number, {
                            name: name, namespace: namespace, lang_code: lang_code, parameters: parameters
                          }, nil).present?
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
    false
  end

  # Bandejas Twilio no tienen catalogo de plantillas de Meta -- el trigger
  # elige una plantilla real de Twilio (content_sid, ya sincronizada via
  # Twilio::TemplateSyncService) en vez de name/namespace/lang_code. Mismo
  # mecanismo que ya usa Calendario::WelcomeBotFlowRunner#send_whatsapp_buttons
  # para los botones del bot de bienvenida.
  def twilio_whatsapp_with_content_sid?
    inbox.twilio_whatsapp? && trigger.template_params['content_sid'].present?
  end

  # Bug real #3 de la auditoria: antes se arrancaba la sesion interactiva (o
  # se aplicaba la exencion del bot de bienvenida) ANTES de intentar el
  # envio real -- si Twilio rechazaba el mensaje, quedaba una sesion activa
  # esperando la respuesta a un mensaje que el paciente nunca recibio. Ahora
  # eso solo pasa DESPUES de confirmar que el envio fue exitoso.
  def send_twilio_template_message
    conversation = find_or_create_conversation
    return false if conversation.blank?

    content_variables = resolve_content_variables
    if incomplete_variable_mapping?(content_variables)
      warn_incomplete_variable_mapping(conversation, content_variables)
      return false
    end

    # BUG REAL encontrado 2026-11-26: contact.phone_number no lleva el
    # prefijo "whatsapp:" -- Twilio lo rechaza con error 21910 ("Invalid
    # From and To pair. From and To should be of the same channel") porque
    # el messaging_service_sid configurado es de WhatsApp. conversation.contact_inbox.source_id
    # ya trae el prefijo correcto -- mismo patron que
    # Calendario::WelcomeBotMessaging#send_whatsapp_buttons, que nunca tuvo este bug.
    message = build_twilio_message(conversation)
    result = Twilio::SendOnTwilioService.new(message: message).send_csat_template_message(
      phone_number: conversation.contact_inbox.source_id, content_sid: trigger.template_params['content_sid'],
      content_variables: content_variables
    )
    return false unless apply_send_result(message, result)

    start_or_exempt_bot_session(conversation, message)
    true
  end

  def start_or_exempt_bot_session(conversation, message)
    if bot_session.interactive?
      bot_session.start!(conversation, source_message_sid: message.source_id)
    else
      Calendario::WelcomeBotExemption.new(conversation: conversation).apply!
    end
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
    success = result[:success].present?
    message.source_id = result[:message_id] if success && result[:message_id].present?
    message.status = :failed unless success
    message.save!
    success
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
  #
  # BUG REAL encontrado 2026-11-26: para plantillas Twilio, processed_params.body
  # usa placeholders numerados estilo Twilio ("{{1}}", "{{2}}"...), no
  # expresiones Liquid -- pasarlos por el Liquid de preview_template_params
  # los interpreta como literales numericos y el preview mostraba "Hola 1,
  # tu cita de 2 es hoy a las 3" en vez de los datos reales (el envio real a
  # Twilio seguia bien, solo este texto local/nota de prueba salia roto).
  def preview_text
    numbered_placeholder_preview_text || liquid_preview_text
  end

  def numbered_placeholder_preview_text
    mapping = trigger.template_params['variable_mapping']
    return if mapping.blank? || mapping.keys.none? { |key| key.to_s.match?(/\A\d+\z/) }

    text = join_sections(trigger.effective_template_params['processed_params'])
    return if text.blank?

    content_variables = resolve_content_variables
    text.gsub(/\{\{\s*(\d+)\s*\}\}/) { content_variables[Regexp.last_match(1)].presence || Regexp.last_match(0) }
  end

  def liquid_preview_text
    join_sections(preview_template_params&.dig('processed_params'))
  end

  def join_sections(params)
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
end

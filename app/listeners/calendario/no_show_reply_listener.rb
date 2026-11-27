# Fase 1 del plan de Notificaciones (ver docs/designs/
# calendario-bienvenida-bot-notificaciones.md): el envio del mensaje de
# no-show (con botones "Reprogramar"/"Cancelar") ya lo cubre el
# Calendario::AppointmentEventTrigger existente (on_status_change,
# target_status: no_show) -- lo unico nuevo aqui es reaccionar cuando el
# paciente responde.
#
# Por que mirar el texto en vez de un "payload" de boton: Twilio manda el
# texto visible del boton por el mismo campo Body que un mensaje de texto
# normal (confirmado en app/jobs/webhooks/twilio_events_job.rb); el whitelist
# del webhook (app/controllers/twilio/callback_controller.rb) ni siquiera
# incluye ButtonText/ButtonPayload, asi que hacer match por contenido es lo
# unico disponible hoy (ver "Open Decisions" del design doc).
#
# "Reprogramar" NO intenta ofrecer un nuevo horario solo -- eso requeriria
# chequear disponibilidad real, que es trabajo de la Fase 2 (bot de
# Bienvenida) o de un humano. Por ahora deja la cita en pendiente + nota
# privada para que el staff la reagende desde la UI que ya existe
# (RescheduleAppointmentModal) -- "a medida que vayamos avanzando, vamos
# perfeccionando el sistema", pedido explicito del usuario.
class Calendario::NoShowReplyListener < BaseListener
  include Calendario::AppointmentReplyKeywordClassifier

  def message_created(event)
    message, account = extract_message_and_account(event)
    return if skip?(message)
    # Bug real encontrado en auditoria con Codex 2026-11-27: este listener
    # corre sobre CUALQUIER mensaje entrante del contacto, sin mirar si hay
    # una sesion de bot activa esperando respuesta para OTRA cita mas
    # reciente en la misma conversacion (ej. el bot de bienvenida/triaje
    # general, o un recordatorio interactivo) -- un simple "Cancelar" dirigido
    # a esa cita nueva terminaba cancelando, por error, una cita de no-show
    # vieja y completamente distinta. Si hay una sesion activa, esa
    # respuesta es suya, no de este listener basado en keywords.
    return if Calendario::BotSession.active.exists?(conversation: message.conversation)

    appointment = recent_no_show_appointment_for(message.conversation)
    return if appointment.blank?

    case classify_appointment_reply(message.content)
    when :reschedule then handle_reschedule(appointment, message.conversation)
    when :cancel then appointment.cancel!
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  private

  # Mismo guard que Calendario::WelcomeBotListener -- un chat historico
  # importado jamas debe poder cancelar/reagendar una cita real solo porque
  # su texto contiene "cancelar"/"reprogramar" por coincidencia.
  def skip?(message)
    return true unless message.incoming? && !message.private?
    return true if message.content_attributes['historical_import']

    message.content.blank?
  end

  # El status vuelve a :no_show solo via un nuevo disparo del trigger de
  # no_show (otra cita futura) -- una vez esta se mueve a :pending o
  # :cancelled, deja de calificar aqui por su cuenta, sin necesitar una tabla
  # aparte para marcar "ya se respondio esta".
  def recent_no_show_appointment_for(conversation)
    contact_id = conversation.contact_id
    return if contact_id.blank?

    fired_appointment_ids = Calendario::AppointmentTriggerFiring
                            .joins(:trigger)
                            .where(calendario_appointment_event_triggers: { trigger_kind: 'on_status_change', target_status: 'no_show' })
                            .select(:appointment_id)

    Calendario::Appointment
      .where(account_id: conversation.account_id, contact_id: contact_id, status: :no_show, id: fired_appointment_ids)
      .order(starts_at: :desc)
      .first
  end

  # Calendario::SpanishDateFormatter (no I18n.l) a proposito -- este listener
  # corre dentro de EventDispatcherJob (background), sin locale de
  # request/usuario atado; I18n.l con el locale global (casi siempre :en en
  # ese contexto) dejaba la fecha en ingles. Fecha en letras, no numerica --
  # mismo pedido explicito del usuario que aplica a toda plantilla que lee
  # el paciente (clientes de +60 anios, DD/MM/AAAA se presta a confusion).
  def handle_reschedule(appointment, conversation)
    appointment.update!(status: :pending)
    zone = appointment.account.reporting_timezone.presence || 'UTC'
    fecha = Calendario::SpanishDateFormatter.long_date_time(appointment.starts_at.in_time_zone(zone))
    conversation.messages.create!(
      account: conversation.account, inbox: conversation.inbox, sender: nil, private: true,
      message_type: :outgoing,
      content: "El paciente respondió que desea reprogramar su cita de #{appointment.service.name} " \
               "del #{fecha}. Quedó en estado Pendiente para reagendar."
    )
  end
end

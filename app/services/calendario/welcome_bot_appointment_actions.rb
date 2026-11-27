# Acciones del flujo de "cita existente" del bot de bienvenida -- separado
# del motor generico de pasos (Calendario::WelcomeBotFlowRunner) para que
# esa clase no siga creciendo. El runner instancia esto y le delega cuando
# step['type'] es uno de los tipos de accion de cita (ver el comentario de
# esquema en Calendario::WelcomeBotFlow).
#
# Cada metodo publico termina la sesion (end_session!) salvo
# handle_lookup_appointment cuando SI encuentra una cita: ese paso espera la
# respuesta del paciente (Reagendar/Cancelar/Hablar con recepcion), igual
# que un "ask" normal.
class Calendario::WelcomeBotAppointmentActions
  include Calendario::WelcomeBotMessaging

  pattr_initialize [:conversation!, :message!]

  delegate :account, :inbox, to: :conversation

  DEFAULT_EMPTY_APPOINTMENT_MESSAGE =
    'No encontramos citas próximas asociadas a tu número. Te comunico con recepción para ayudarte.'.freeze
  DEFAULT_APPOINTMENT_CONFIRMATION_TEMPLATE =
    '¿Te refieres a tu cita del {{ appointment.date }} a las {{ appointment.time }} ' \
    'con {{ appointment.professional_name }} ({{ appointment.service_name }})?'.freeze
  DEFAULT_LOOKUP_OPTIONS = ['Reagendar', 'Cancelar', 'Hablar con recepción'].freeze
  DEFAULT_WAITLIST_KEYWORD = 'lista de espera'.freeze
  # Bug real 2026-11-26: el texto fijo prometia "en breve" sin importar la
  # hora -- ver Calendario::WelcomeBotMessaging#office_status_notice (mismo
  # fix que ya se aplico al handoff general).
  DEFAULT_RESCHEDULE_ACK_MESSAGE =
    'Hemos recibido tu solicitud de reagendamiento. {{ office_status_notice }}'.freeze
  DEFAULT_CONFIRMATION_ACK_MESSAGE =
    '¡Gracias por confirmar! Te esperamos en tu cita.'.freeze
  DEFAULT_ALREADY_CONFIRMED_MESSAGE =
    'Tu cita ya estaba confirmada. ¡Te esperamos!'.freeze
  DEFAULT_HANDOFF_ACK_MESSAGE =
    '¡Gracias por adelantarnos tus datos! Ya se le notificó a recepción para que continúe con tu atención. ' \
    'Si necesitas algo más, escríbenos por este mismo medio.'.freeze

  # Busca la cita futura del contacto -- SIEMPRE via conversation.contact,
  # nunca por telefono "a mano", para que sea imposible mostrarle a un
  # paciente la cita de otro. Solo opera sobre la mas proxima si hay varias;
  # eso es un limite conocido de esta primera version.
  def handle_lookup_appointment(session, step)
    appointment = conversation.contact.calendario_appointments.upcoming.order(:starts_at).first
    return handle_no_upcoming_appointment(session, step) if appointment.blank?

    session.update!(answers: session.answers.merge('_appointment_id' => appointment.id))
    ask_step = lookup_confirmation_step(step, appointment)

    sent_message = step['content_sid'].present? ? send_whatsapp_buttons(ask_step) : send_text_question(ask_step)
    session.update!(last_prompted_at: Time.current, reminder_count: 0, source_message_sid: sent_message&.source_id)
  end

  # La respuesta a "lista de espera o definitiva" es el mensaje entrante que
  # disparo este mismo ciclo (el paso anterior era un "ask" normal que ya la
  # guardo en session.answers via Calendario::WelcomeBotFlowRunner#advance!)
  # -- usar message.content directamente evita adivinar que indice de
  # answers corresponde al paso anterior si hubiera ramificaciones.
  # Bug real encontrado en auditoria con Codex 2026-11-27 (hallazgo #8): esto
  # no tenia NINGUN guard de estado -- una accion tardia (ej. el paciente
  # toca "Cancelar" en un mensaje viejo de WhatsApp despues de que la cita ya
  # quedo "atendida" o ya fue cancelada por otro medio) sobreescribia un
  # estado ya definitivo. Mismo criterio que perform_confirmation_step: si no
  # esta en un estado donde cancelar tiene sentido (pendiente/confirmada), se
  # trata como cita no encontrada -- se transfiere a recepcion en vez de
  # mutar un estado inconsistente. appointment.with_lock cierra tambien la
  # carrera de dos respuestas casi simultaneas para el mismo boton (ambas
  # pasando el chequeo antes de que ninguna escribiera).
  def perform_cancellation_step(session, step)
    appointment = located_appointment(session)
    return handoff_for_missing_appointment(session, step) if appointment.blank?

    cancelled = appointment.with_lock do
      next false unless cancellable_state?(appointment)

      appointment.cancel!
      true
    end
    return handoff_for_missing_appointment(session, step) unless cancelled

    finish_cancellation(session, step, appointment, wants_waitlist?(step))
  end

  def perform_reschedule_step(session, step)
    appointment = located_appointment(session)
    return handoff_for_missing_appointment(session, step) if appointment.blank?

    reopened = appointment.with_lock do
      next false unless cancellable_state?(appointment)

      appointment.update!(status: :pending)
      true
    end
    return handoff_for_missing_appointment(session, step) unless reopened

    assign_available_agent if conversation.assignee_id.blank?
    create_private_note("Cita ##{appointment.id}: el paciente solicitó reagendar vía bot de bienvenida. Reagendar manualmente.")
    ack_text = resolved_text(step, 'ack_message_key', 'ack_message', DEFAULT_RESCHEDULE_ACK_MESSAGE)
    send_text_question('ask' => render_liquid(ack_text, 'office_status_notice' => office_status_notice))

    end_session!(session)
  end

  # Botón "Confirmar" (pedido explicito del usuario 2026-11-26, pensado para
  # los recordatorios de cita con botones -- 60min/24h/semana, fase 2). A
  # diferencia de cancelar/reagendar, confirmar una cita YA confirmada es un
  # no-op amigable (el paciente pudo tocar el boton dos veces, o volver a un
  # mensaje viejo de WhatsApp) -- no vuelve a crear nota/asignar agente. Si
  # la cita ya no esta en un estado confirmable (cancelada, atendida,
  # no_show), se trata igual que una cita no encontrada: se transfiere a
  # recepcion en vez de confirmar un estado inconsistente.
  def perform_confirmation_step(session, step)
    appointment = located_appointment(session)
    return handoff_for_missing_appointment(session, step) if appointment.blank?

    outcome = appointment.with_lock do
      next :already_confirmed if appointment.confirmed?
      next :invalid unless appointment.pending?

      appointment.confirm!
      :confirmed
    end

    if outcome == :already_confirmed
      send_text_question('ask' => resolved_text(step, 'already_confirmed_message_key', 'already_confirmed_message',
                                                DEFAULT_ALREADY_CONFIRMED_MESSAGE))
      return end_session!(session)
    end
    return handoff_for_missing_appointment(session, step) if outcome == :invalid

    assign_available_agent if conversation.assignee_id.blank?
    create_private_note("Cita ##{appointment.id} confirmada por el paciente vía bot de bienvenida.")
    send_text_question('ask' => resolved_text(step, 'ack_message_key', 'ack_message', DEFAULT_CONFIRMATION_ACK_MESSAGE))

    end_session!(session)
  end

  def perform_handoff_step(session, step, note: 'El paciente solicitó hablar con recepción vía bot de bienvenida.')
    assign_available_agent if conversation.assignee_id.blank?
    create_private_note(note)
    send_text_question('ask' => resolved_text(step, 'ack_message_key', 'ack_message', DEFAULT_HANDOFF_ACK_MESSAGE))

    end_session!(session)
  end

  private

  # Unico criterio compartido por las 3 acciones de sesion (cancelar,
  # reagendar, confirmar): solo tiene sentido actuar sobre un estado NO
  # definitivo. Una vez atendida/no-show/cancelada, cualquier accion tardia
  # se trata como cita no encontrada.
  def cancellable_state?(appointment)
    appointment.pending? || appointment.confirmed?
  end

  def wants_waitlist?(step)
    normalize(message.content).include?(normalize(step['waitlist_keyword'].presence || DEFAULT_WAITLIST_KEYWORD))
  end

  def finish_cancellation(session, step, appointment, wants_waitlist)
    Calendario::WaitlistFulfillmentService.new(appointment: appointment).reactivate! if wants_waitlist

    assign_available_agent if conversation.assignee_id.blank?
    create_private_note(
      "Cita ##{appointment.id} cancelada vía bot de bienvenida " \
      "(#{wants_waitlist ? 'reactivo lista de espera' : 'cancelacion definitiva'})."
    )
    send_text_question('ask' => resolved_text(step, 'ack_message_key', 'ack_message', DEFAULT_HANDOFF_ACK_MESSAGE))

    end_session!(session)
  end

  def handle_no_upcoming_appointment(session, step)
    empty_message = resolved_text(step, 'empty_message_key', 'empty_message', DEFAULT_EMPTY_APPOINTMENT_MESSAGE)
    empty_step = step.merge('ack_message' => empty_message, 'ack_message_key' => nil)
    perform_handoff_step(session, empty_step, note: 'No se encontraron citas futuras para este contacto.')
  end

  def handoff_for_missing_appointment(session, step)
    perform_handoff_step(session, step, note: 'No se pudo recuperar la cita original; se transfiere a un agente.')
  end

  def lookup_confirmation_step(step, appointment)
    ask_template = resolved_text(step, 'ask_template_key', 'ask_template', DEFAULT_APPOINTMENT_CONFIRMATION_TEMPLATE)
    confirmation_text = render_appointment_liquid(ask_template, appointment)
    step.merge(
      'ask' => confirmation_text, 'options' => Array(step['options']).presence || DEFAULT_LOOKUP_OPTIONS,
      'dynamic_body_variable' => true
    )
  end

  # Re-resuelve la cita SIEMPRE a traves de conversation.contact (nunca por
  # el id crudo solo) -- aunque el id ya se guardo en un paso anterior de
  # esta misma sesion, esto garantiza que jamas se opere sobre una cita que
  # no pertenezca al contacto de esta conversacion.
  def located_appointment(session)
    appointment_id = session.answers['_appointment_id']
    return if appointment_id.blank?

    conversation.contact.calendario_appointments.find_by(id: appointment_id)
  end

  def render_appointment_liquid(template, appointment)
    render_liquid(template, 'appointment' => Calendario::AppointmentDrop.new(appointment))
  end

  def end_session!(session)
    session.end!
  end
end

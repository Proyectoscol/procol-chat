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
  DEFAULT_RESCHEDULE_ACK_MESSAGE =
    'Hemos recibido tu solicitud de reagendamiento. Un asesor te contactará en breve para coordinar la nueva fecha.'.freeze
  DEFAULT_HANDOFF_ACK_MESSAGE = 'Entendido, te comunico con recepción para ayudarte.'.freeze

  # Busca la cita futura del contacto -- SIEMPRE via conversation.contact,
  # nunca por telefono "a mano", para que sea imposible mostrarle a un
  # paciente la cita de otro. Solo opera sobre la mas proxima si hay varias;
  # eso es un limite conocido de esta primera version.
  def handle_lookup_appointment(session, step)
    appointment = conversation.contact.calendario_appointments.upcoming.order(:starts_at).first
    return handle_no_upcoming_appointment(session, step) if appointment.blank?

    session.update!(answers: session.answers.merge('_appointment_id' => appointment.id))
    ask_step = lookup_confirmation_step(step, appointment)

    step['content_sid'].present? ? send_whatsapp_buttons(ask_step) : send_text_question(ask_step)
    session.update!(last_prompted_at: Time.current, reminder_count: 0)
  end

  # La respuesta a "lista de espera o definitiva" es el mensaje entrante que
  # disparo este mismo ciclo (el paso anterior era un "ask" normal que ya la
  # guardo en session.answers via Calendario::WelcomeBotFlowRunner#advance!)
  # -- usar message.content directamente evita adivinar que indice de
  # answers corresponde al paso anterior si hubiera ramificaciones.
  def perform_cancellation_step(session, step)
    appointment = located_appointment(session)
    return handoff_for_missing_appointment(session, step) if appointment.blank?

    wants_waitlist = normalize(message.content).include?(
      normalize(step['waitlist_keyword'].presence || DEFAULT_WAITLIST_KEYWORD)
    )

    appointment.cancel!
    Calendario::WaitlistFulfillmentService.new(appointment: appointment).reactivate! if wants_waitlist

    assign_available_agent if conversation.assignee_id.blank?
    create_private_note(
      "Cita ##{appointment.id} cancelada vía bot de bienvenida " \
      "(#{wants_waitlist ? 'reactivo lista de espera' : 'cancelacion definitiva'})."
    )

    end_session!(session)
  end

  def perform_reschedule_step(session, step)
    appointment = located_appointment(session)
    return handoff_for_missing_appointment(session, step) if appointment.blank?

    appointment.update!(status: :pending)
    assign_available_agent if conversation.assignee_id.blank?
    create_private_note("Cita ##{appointment.id}: el paciente solicitó reagendar vía bot de bienvenida. Reagendar manualmente.")
    send_text_question('ask' => step['ack_message'].presence || DEFAULT_RESCHEDULE_ACK_MESSAGE)

    end_session!(session)
  end

  def perform_handoff_step(session, step, note: 'El paciente solicitó hablar con recepción vía bot de bienvenida.')
    assign_available_agent if conversation.assignee_id.blank?
    create_private_note(note)
    send_text_question('ask' => step['ack_message'].presence || DEFAULT_HANDOFF_ACK_MESSAGE)

    end_session!(session)
  end

  private

  def handle_no_upcoming_appointment(session, step)
    empty_step = step.merge('ack_message' => step['empty_message'].presence || DEFAULT_EMPTY_APPOINTMENT_MESSAGE)
    perform_handoff_step(session, empty_step, note: 'No se encontraron citas futuras para este contacto.')
  end

  def handoff_for_missing_appointment(session, step)
    perform_handoff_step(session, step, note: 'No se pudo recuperar la cita original; se transfiere a un agente.')
  end

  def lookup_confirmation_step(step, appointment)
    confirmation_text = render_appointment_liquid(
      step['ask_template'].presence || DEFAULT_APPOINTMENT_CONFIRMATION_TEMPLATE, appointment
    )
    step.merge('ask' => confirmation_text, 'options' => Array(step['options']).presence || DEFAULT_LOOKUP_OPTIONS)
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
    Liquid::Template.parse(template).render!('appointment' => Calendario::AppointmentDrop.new(appointment))
  rescue Liquid::Error
    template
  end

  def end_session!(session)
    session.update!(status: 'handed_off')
    inbox.update!(enable_auto_assignment: true) unless other_active_sessions_for_inbox?
  end

  def other_active_sessions_for_inbox?
    Calendario::BotSession.active
                          .joins(:welcome_bot_flow)
                          .where(calendario_welcome_bot_flows: { inbox_id: inbox.id })
                          .where.not(conversation_id: conversation.id)
                          .exists?
  end
end

# Procesa UN mensaje entrante para el bot de Bienvenida: si la conversacion
# no tiene sesion activa, busca que flujo matchea (por palabra clave o
# default, ver Calendario::WelcomeBotFlow.match_for) y arranca la primera
# pregunta; si ya tiene sesion, guarda la respuesta y avanza al siguiente
# paso aplicable, o entrega la conversacion a un humano si no quedan pasos.
#
# Los pasos de tipo "accion" (cita existente -- lookup_appointment,
# perform_cancellation, request_reschedule, confirm_appointment, handoff) se delegan a
# Calendario::WelcomeBotAppointmentActions, que es quien toca
# Calendario::Appointment; este runner solo sabe el motor generico de
# pasos/ramificacion.
#
# Apaga inbox.enable_auto_assignment mientras el bot este "dueno" de la
# conversacion -- hallazgo real de la auditoria de arquitectura: toda
# conversacion nueva nace con status: open, y
# AutoAssignmentHandler#conversation_status_changed_to_open? es cierto para
# CUALQUIER alta (previous_changes.key?(:id)), asi que sin este toggle la
# auto-asignacion le gana al bot en la primera cita. Ver
# docs/designs/calendario-bienvenida-bot-notificaciones.md.
class Calendario::WelcomeBotFlowRunner
  include Calendario::WelcomeBotMessaging

  # `message` solo hace falta para el camino normal (reaccionar a un mensaje
  # entrante real -- matchea flujo por palabra clave y, si ya hay sesion,
  # guarda la respuesta). Un disparo manual desde Ajustes/conversacion
  # (Api::V1::Accounts::Conversations::WelcomeBotTriggersController) pasa
  # `flow` directo, sin message, para arrancar una sesion nueva sin esperar
  # ningun mensaje del paciente.
  pattr_initialize [:conversation!, { message: nil }, { flow: nil }]

  def perform
    active_session.present? ? advance! : start!
  end

  private

  delegate :account, :inbox, to: :conversation

  def active_session
    @active_session ||= Calendario::BotSession.active.find_by(conversation: conversation)
  end

  def appointment_actions
    @appointment_actions ||= Calendario::WelcomeBotAppointmentActions.new(conversation: conversation, message: message)
  end

  def start!
    selected_flow = flow || Calendario::WelcomeBotFlow.match_for(inbox, message&.content)
    return if selected_flow.blank? || selected_flow.steps.blank?

    inbox.update!(enable_auto_assignment: false)
    # La auto-asignacion corre en el after_save de ConversationBuilder al
    # CREAR la conversacion -- eso pasa antes de que el mensaje (y por lo
    # tanto este runner) exista. Para una conversacion nueva, enable_auto_
    # assignment arriba todavia estaba en true en ese instante, asi que
    # pudo alcanzar a asignarse a un humano en esa ventana. Deshacerlo aqui
    # es la correccion, no solo prevencion hacia adelante.
    conversation.update!(assignee_id: nil) if conversation.assignee_id.present?
    session = Calendario::BotSession.create!(
      account: account, conversation: conversation, welcome_bot_flow: selected_flow, current_step: 0
    )
    ask_current_step(session)
  end

  def advance!
    session = active_session
    step = session.current_step_config
    return finish!(session) if step.blank?
    return handle_unmatched_answer(session, step) if unmatched_answer?(step, message.content)

    answers = session.answers.merge(session.current_step.to_s => message.content)
    session.update!(answers: answers)

    move_to_next_step!(session)
  end

  # Un paso con "options"/"buttons" espera UNA de esas respuestas exactas
  # (normalizada) -- cualquier otra cosa (texto libre, una pregunta del
  # paciente, un "????") es una respuesta "no reconocida". Un paso SIN
  # opciones (ej. "Con que entidad estas afiliado?") siempre acepta lo que
  # sea, nunca es "no reconocida".
  def unmatched_answer?(step, answer)
    options = step_options(step)
    options.present? && options.none? { |option| normalize(option) == normalize(answer) }
  end

  def step_options(step)
    Array(step['options'] || step['buttons'])
  end

  # Pedido explicito del usuario (rediseño 2026-11-25): que pasa cuando el
  # cliente escribe algo que no esta parametrizado debe ser una decision
  # EXPLICITA y editable por paso ("on_unmatched"), no un accidente del
  # motor -- antes de esto, cualquier respuesta libre simplemente no
  # matcheaba ningun "if" de los pasos siguientes y terminaba en finish!
  # por casualidad, sin que nadie lo hubiera decidido asi.
  ON_UNMATCHED_HANDLERS = {
    'repeat' => :repeat_current_step,
    'continue' => :continue_with_free_text,
    'handoff' => :handoff_for_unmatched_answer
  }.freeze

  def handle_unmatched_answer(session, step)
    handler = ON_UNMATCHED_HANDLERS[step['on_unmatched']] || :handoff_for_unmatched_answer
    send(handler, session, step)
  end

  def repeat_current_step(session, _step)
    step = session.current_step_config.merge('ask' => "No entendí tu respuesta. #{session.current_step_config['ask']}")
    step['content_sid'].present? ? send_whatsapp_buttons(step) : send_text_question(step)
    session.update!(last_prompted_at: Time.current)
  end

  def continue_with_free_text(session, _step)
    answers = session.answers.merge(session.current_step.to_s => message.content)
    session.update!(answers: answers)
    move_to_next_step!(session)
  end

  def handoff_for_unmatched_answer(session, _step)
    finish!(session, note: "El paciente respondió algo no reconocido en este paso (\"#{message.content}\"), se transfiere a un agente.")
  end

  # Usado tanto por advance! (el paciente acaba de responder el paso actual)
  # como por los pasos de accion (cancelar/reagendar/transferir -- se
  # ejecutan solos, sin esperar respuesta, y llaman esto para seguir).
  def move_to_next_step!(session)
    next_step = next_applicable_step_index(session)
    if next_step.nil?
      finish!(session)
    else
      session.update!(current_step: next_step, reminder_count: 0)
      ask_current_step(session)
    end
  end

  # Un paso con "if" solo aplica si la respuesta del paso que referencia
  # coincide exactamente -- permite ramificar (ej. "Cual EPS?" solo si la
  # respuesta anterior fue "EPS/aseguradora").
  def next_applicable_step_index(session)
    steps = session.welcome_bot_flow.steps
    ((session.current_step + 1)...steps.size).find do |index|
      applicable_step?(steps[index], session.answers)
    end
  end

  def applicable_step?(step, answers)
    condition = step['if']
    return true if condition.blank?

    normalize(answers[condition['step'].to_s]) == normalize(condition['equals'])
  end

  ACTION_STEP_HANDLERS = {
    'lookup_appointment' => :handle_lookup_appointment,
    'perform_cancellation' => :perform_cancellation_step,
    'request_reschedule' => :perform_reschedule_step,
    'confirm_appointment' => :perform_confirmation_step,
    'handoff' => :perform_handoff_step
  }.freeze

  def ask_current_step(session)
    step = session.current_step_config
    return finish!(session) if step.blank?
    return handle_notify_step(session, step) if step['type'] == 'notify'

    handler = ACTION_STEP_HANDLERS[step['type']]
    return appointment_actions.public_send(handler, session, step) if handler

    step['content_sid'].present? ? send_whatsapp_buttons(step) : send_text_question(step)
    session.update!(last_prompted_at: Time.current, reminder_count: 0)
  end

  # Paso puramente informativo -- manda un mensaje sin botones y sigue de
  # inmediato al proximo paso aplicable, igual que los pasos de accion
  # (cancelar/reagendar/handoff), pero sin tocar Calendario::Appointment.
  # Util para cualquier mensaje "de paso" que no requiere respuesta (ej. el
  # aviso de que ginecologia no atiende pacientes en embarazo).
  def handle_notify_step(session, step)
    text = resolved_text(step, 'ack_message_key', 'ack_message', '')
    send_text_question('ask' => text) if text.present?
    move_to_next_step!(session)
  end

  def finish!(session, note: nil)
    session.update!(status: 'handed_off')
    # Solo reactiva la auto-asignacion si NINGUNA otra conversacion de esta
    # misma bandeja sigue en triage -- es un flag de la bandeja completa,
    # no de una sola conversacion; reactivarlo con otra sesion todavia
    # activa le devolveria la carrera a la auto-asignacion contra ESA otra.
    inbox.update!(enable_auto_assignment: true) unless other_active_sessions_for_inbox?
    hand_off_to_human(session, note: note)
  end

  def other_active_sessions_for_inbox?
    Calendario::BotSession.active
                          .joins(:welcome_bot_flow)
                          .where(calendario_welcome_bot_flows: { inbox_id: inbox.id })
                          .where.not(conversation_id: conversation.id)
                          .exists?
  end

  # Key de Calendario::MessageTemplate editable desde el admin -- fase de
  # rediseño 2026-11-25: antes era un texto fijo que siempre decia "Mi
  # nombre es Beatriz", lo cual era incorrecto en cuanto la asignacion deja
  # de ser siempre la misma persona (ver Calendario::WelcomeBotAssignmentService,
  # round-robin real entre todos los agentes).
  HANDOFF_MESSAGE_KEY = 'bot_handoff_default'.freeze
  DEFAULT_HANDOFF_MESSAGE = 'Gracias por indicarnos esos datos. {{ agent_intro }}' \
                            '¿Hay algo más que debamos saber, o prefieres esperar nuestra respuesta?'.freeze

  def hand_off_to_human(session, note: nil)
    create_private_note(
      note.presence || "Triage completado (#{session.welcome_bot_flow.name}). Respuestas: " \
                       "#{session.answers.values.join(' / ')}"
    )
    # Asignar PRIMERO: el nombre del agente real solo se conoce despues de
    # que assign_available_agent corre (round-robin), asi el mensaje nunca
    # queda desfasado respecto a quien realmente quedo asignado.
    assign_available_agent
    send_text_question('ask' => handoff_message)
  end

  def handoff_message
    template = Calendario::MessageTemplate.active_body(account, HANDOFF_MESSAGE_KEY).presence || DEFAULT_HANDOFF_MESSAGE
    agent_name = conversation.reload.assignee&.name
    agent_intro = agent_name.present? ? "Mi nombre es *#{agent_name}* y me encargaré de tu atención. " : ''
    render_liquid(template, 'agent_intro' => agent_intro, 'office_status_notice' => office_status_notice)
  end
end

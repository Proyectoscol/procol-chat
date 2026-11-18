# Procesa UN mensaje entrante para el bot de Bienvenida: si la conversacion
# no tiene sesion activa, busca que flujo matchea (por palabra clave o
# default, ver Calendario::WelcomeBotFlow.match_for) y arranca la primera
# pregunta; si ya tiene sesion, guarda la respuesta y avanza al siguiente
# paso aplicable, o entrega la conversacion a un humano si no quedan pasos.
#
# Apaga inbox.enable_auto_assignment mientras el bot este "dueno" de la
# conversacion -- hallazgo real de la auditoria de arquitectura: toda
# conversacion nueva nace con status: open, y
# AutoAssignmentHandler#conversation_status_changed_to_open? es cierto para
# CUALQUIER alta (previous_changes.key?(:id)), asi que sin este toggle la
# auto-asignacion le gana al bot en la primera cita. Ver
# docs/designs/calendario-bienvenida-bot-notificaciones.md.
class Calendario::WelcomeBotFlowRunner
  pattr_initialize [:message!]

  def perform
    active_session.present? ? advance! : start!
  end

  private

  delegate :conversation, to: :message
  delegate :account, :inbox, to: :conversation

  def active_session
    @active_session ||= Calendario::BotSession.active.find_by(conversation: conversation)
  end

  def start!
    flow = Calendario::WelcomeBotFlow.match_for(inbox, message.content)
    return if flow.blank? || flow.steps.blank?

    inbox.update!(enable_auto_assignment: false)
    # La auto-asignacion corre en el after_save de ConversationBuilder al
    # CREAR la conversacion -- eso pasa antes de que el mensaje (y por lo
    # tanto este runner) exista. Para una conversacion nueva, enable_auto_
    # assignment arriba todavia estaba en true en ese instante, asi que
    # pudo alcanzar a asignarse a un humano en esa ventana. Deshacerlo aqui
    # es la correccion, no solo prevencion hacia adelante.
    conversation.update!(assignee_id: nil) if conversation.assignee_id.present?
    session = Calendario::BotSession.create!(
      account: account, conversation: conversation, welcome_bot_flow: flow, current_step: 0
    )
    ask_current_step(session)
  end

  def advance!
    session = active_session
    step = session.current_step_config
    return finish!(session) if step.blank?

    answers = session.answers.merge(session.current_step.to_s => message.content)
    session.update!(answers: answers)

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

  def normalize(text)
    Calendario::WelcomeBotFlow.normalize(text)
  end

  def ask_current_step(session)
    step = session.current_step_config
    return finish!(session) if step.blank?

    body = step['ask'].to_s
    body += "\n\n#{Array(step['options']).join("\n")}" if step['options'].present?
    create_private_note(body)
    session.update!(last_prompted_at: Time.current, reminder_count: 0)
  end

  # Igual que Calendario::AppointmentTriggerRunner#create_private_note --
  # ver esa clase para por que nota privada en vez de mensaje real (pedido
  # explicito del usuario antes de produccion).
  def create_private_note(body)
    conversation.messages.create!(
      account: account, inbox: inbox, private: true, message_type: :outgoing,
      content: "[BOT DE BIENVENIDA -- modo de prueba, nunca se envio un mensaje real]\n\n#{body}"
    )
  end

  def finish!(session)
    session.update!(status: 'handed_off')
    # Solo reactiva la auto-asignacion si NINGUNA otra conversacion de esta
    # misma bandeja sigue en triage -- es un flag de la bandeja completa,
    # no de una sola conversacion; reactivarlo con otra sesion todavia
    # activa le devolveria la carrera a la auto-asignacion contra ESA otra.
    inbox.update!(enable_auto_assignment: true) unless other_active_sessions_for_inbox?
    hand_off_to_human(session)
  end

  def other_active_sessions_for_inbox?
    Calendario::BotSession.active
                          .joins(:welcome_bot_flow)
                          .where(calendario_welcome_bot_flows: { inbox_id: inbox.id })
                          .where.not(conversation_id: conversation.id)
                          .exists?
  end

  # ActionService#assign_team (ya existente, usado por Automatizaciones) --
  # equipo configurable mas adelante; por ahora deja la nota y confia en la
  # auto-asignacion (ya reactivada arriba si corresponde) para tomarla como
  # cualquier otra conversacion abierta sin asignar.
  def hand_off_to_human(session)
    create_private_note(
      "Triage completado (#{session.welcome_bot_flow.name}). Respuestas: " \
      "#{session.answers.values.join(' / ')}"
    )
  end
end

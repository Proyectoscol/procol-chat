class Calendario::WelcomeBotListener < BaseListener
  def message_created(event)
    message, account = extract_message_and_account(event)
    return unless message.incoming? && !message.private?
    # Nunca reaccionar a un mensaje historico importado (ej. bulk-import de
    # exports de WhatsApp) -- ver incidente documentado en
    # data_imports/.../INCIDENTE_welcome_bot_import.md: sin este guard, 166
    # conversaciones importadas se confundieron con conversaciones nuevas de
    # verdad y el bot mando 674 mensajes reales por Twilio a pacientes reales.
    return if message.content_attributes['historical_import']

    conversation = message.conversation
    flow = Calendario::WelcomeBotFlow.match_for(conversation.inbox, message.content, conversation: conversation)
    return if flow.blank?
    return if already_handled_today?(conversation, message)

    Calendario::WelcomeBotFlowRunner.new(conversation: conversation, message: message, flow: flow).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  private

  # Una vez entregada a un agente (triage completo o escalamiento por
  # recordatorios sin respuesta, ver Calendario::WelcomeBotFlowRunner#finish!
  # y Calendario::BotSessionReminderJob#escalate), un mensaje nuevo del mismo
  # contacto NO reinicia el triage si es el MISMO dia calendario (zona de la
  # cuenta, ej. "Bogota" -- nunca UTC del servidor). Si es un dia distinto,
  # SI se reinicia -- pedido explicito del usuario 2026-11-25: "cuando ya un
  # paciente escribe al dia siguiente, nuevamente le enviamos el bot de
  # triaje", reemplaza por completo la vieja feature separada
  # "paciente que regresa" (Calendario::ReturningAppointmentPromptListener,
  # eliminada). Si todavia no hay sesion activa, solo aplica cuando la
  # conversacion ya tiene asignado un agente Y alguna vez corrio una sesion
  # de bot (sin esto ultimo, una conversacion nueva atrapada en la carrera
  # de auto-asignacion -- ver WelcomeBotFlowRunner#start! -- se confunde con
  # una ya entregada y el bot nunca llega a arrancar).
  def already_handled_today?(conversation, message)
    return false if Calendario::BotSession.active.exists?(conversation: conversation)
    # additional_attributes['skip_welcome_bot']: exencion PERMANENTE, no
    # sujeta a la regla de "dia distinto" de abajo -- revisado con Codex
    # 2026-11-26. Una conversacion nacida de una notificacion de cita SIN
    # botones (confirmacion/cancelacion/reprogramacion) nunca debe volver a
    # activar el Triaje general solo porque el paciente respondio, sin
    # importar cuantos dias pasen -- a diferencia del caso de abajo (triage
    # completo real, donde SI tiene sentido reabrir al dia siguiente), aqui
    # nunca hubo ningun triage que "reabrir". Pedido explicito del usuario:
    # "ya debería estar asignado... la atención sea con recepción... sin
    # más mensajes" -- ningún mensaje automático más, periodo.
    return true if conversation.additional_attributes['skip_welcome_bot'].present?
    # BUG REAL encontrado en produccion 2026-11-26 (conversacion de "Nueva
    # Eps"): el agente Beatriz pregunto "De que entidad?" y el paciente
    # respondio un minuto despues -- pero como `new_calendar_day?` solo
    # compara mensajes ENTRANTES entre si, el ultimo entrante previo era de
    # el dia anterior, asi que "dia distinto" disparaba el triaje general
    # encima de la respuesta directa del paciente a su agente. Si el ULTIMO
    # mensaje de la conversacion (en cualquier direccion) fue una respuesta
    # humana real de un agente, el paciente le esta respondiendo a ESE
    # mensaje, sin importar cuantos dias hayan pasado -- nunca reactivar el
    # bot en ese caso.
    return true if responding_to_agent?(conversation, message)
    return false unless conversation.assignee_id.present? && Calendario::BotSession.exists?(conversation: conversation)

    !abandoned_since_last_message?(conversation, message)
  end

  def responding_to_agent?(conversation, message)
    last_message = conversation.messages.where.not(id: message.id).reorder(created_at: :desc).first
    last_message.present? && last_message.human_response?
  end

  # Mismo patron que la vieja Calendario::ReturningAppointmentPromptListener#new_calendar_day? --
  # sin mensaje entrante anterior no hay "otro dia" con que comparar, asi
  # que no aplica (nunca reinicia solo porque "no hay historial").
  #
  # BUG REAL encontrado en produccion 2026-11-25 (ver transcript real,
  # conversacion #292): `Message` tiene `default_scope { order(created_at: :asc) }`
  # -- un `.order(created_at: :desc)` encadenado NO reemplaza un default_scope,
  # lo apila (`ORDER BY created_at ASC, created_at DESC`), y como ambos
  # terminos son la MISMA columna, el resultado queda ascendente de todas
  # formas. Eso hacia que `previous` fuera siempre el PRIMER mensaje de toda
  # la conversacion, nunca el inmediatamente anterior -- cualquier mensaje
  # despues del primer dia se veia como "dia distinto" y reiniciaba el
  # triaje en cada respuesta, incluso segundos despues del handoff anterior.
  # `.reorder` SI reemplaza el default_scope.
  #
  # BUG REAL encontrado en produccion 2026-11-25 (segundo): comparar solo la
  # FECHA calendario reactivaba el triaje con brechas minimas que cruzan
  # medianoche -- paciente escribe 11pm, nadie de recepcion alcanza a
  # contestar, y escribe de nuevo a las 6am (7 horas despues, antes de que
  # abra recepcion) -- eso veia "dia distinto" y reiniciaba el triaje,
  # pidiendole la misma informacion dos veces sin que recepcion siquiera
  # tuviera la oportunidad real de responder. El criterio correcto no es
  # "cambio la fecha", es "ya cerro un dia habil completo sin que
  # respondieran" -- solo reactiva si el horario laboral de ALGUN dia entre
  # el mensaje anterior y este ya CERRO en ese rango (es decir, recepcion
  # tuvo su ventana entera y no respondio). Si `working_hours_enabled` esta
  # apagado en el inbox, cae al criterio viejo (cambio de fecha) como
  # fallback.
  def abandoned_since_last_message?(conversation, message)
    previous = conversation.messages.incoming.where.not(id: message.id).reorder(created_at: :desc).first
    return false if previous.blank?

    inbox = conversation.inbox
    return local_date(conversation, previous.created_at) != local_date(conversation, message.created_at) unless inbox.working_hours_enabled?

    zone = inbox.timezone.presence || 'UTC'
    from_time = previous.created_at.in_time_zone(zone)
    to_time = message.created_at.in_time_zone(zone)
    (from_time.to_date..to_time.to_date).any? do |date|
      working_hours_already_closed_between?(inbox, date, zone, from_time, to_time)
    end
  end

  def working_hours_already_closed_between?(inbox, date, zone, from_time, to_time)
    working_hour = inbox.working_hours.find_by(day_of_week: date.wday)
    return false if working_hour.blank? || working_hour.closed_all_day?

    close_at = date.in_time_zone(zone).change(hour: working_hour.close_hour, min: working_hour.close_minutes)
    close_at > from_time && close_at <= to_time
  end

  def local_date(conversation, time)
    zone = conversation.account.reporting_timezone.presence || 'UTC'
    time.in_time_zone(zone).to_date
  end
end

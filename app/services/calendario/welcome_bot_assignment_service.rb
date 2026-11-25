# Asignacion de agente para el bot de bienvenida -- a diferencia de
# AutoAssignment::AgentAssignmentService (la auto-asignacion generica de
# Chatwoot), esta NUNCA filtra por estar "online": el paciente que escribe
# fuera de horario tiene que quedar igual de asignado que uno que escribe en
# horario laboral, para que Calendario::WelcomeBotListener
# (#restarting_an_already_assigned_conversation?) pueda detectar que la
# conversacion ya fue entregada y no reinicie el triage en cada mensaje
# nuevo. Hallazgo real 2026-11-25: sin esto, fuera de horario
# conversation.assignee_id nunca se llenaba y el triage se repetia sin fin.
#
# Reutiliza el mismo round-robin real (cola en Redis) que usa la
# auto-asignacion generica -- AutoAssignment::InboxRoundRobinService -- solo
# que pasandole TODOS los miembros de la bandeja con cupo, sin interseccion
# con agentes online.
class Calendario::WelcomeBotAssignmentService
  pattr_initialize [:conversation!]

  def perform
    # OJO: `member_ids_with_assignment_capacity` NO sirve aqui -- en Enterprise
    # (ver enterprise/app/models/enterprise/inbox_agent_availability.rb),
    # cuando la cuenta tiene politicas de capacidad configuradas, ese metodo
    # TAMBIEN filtra por agente online (vuelve a introducir el mismo bug que
    # este servicio existe para evitar). `member_ids` (generado por Rails
    # para `has_many :members, through: :inbox_members`) es la membresia
    # pura del inbox, sin ningun filtro de disponibilidad.
    agent_ids = conversation.inbox.member_ids
    return if agent_ids.blank?

    assignee = round_robin_service.available_agent(allowed_agent_ids: agent_ids.map(&:to_s))
    conversation.update!(assignee: assignee) if assignee
  end

  private

  def round_robin_service
    @round_robin_service ||= AutoAssignment::InboxRoundRobinService.new(inbox: conversation.inbox)
  end
end

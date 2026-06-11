# Orquestador del routing de voz (§14.2/§17.2). Corre un pipeline de reglas
# NOMBRADAS en orden; cada una es un objeto con `call(context) → :handled | :continue`.
# La primera que devuelve :handled corta el pipeline y deja su decisión en
# `context.outcome`. VoicemailFallbackRule cierra siempre (cero llamada perdida).
#
# Este servicio sólo DECIDE. La ejecución de los efectos del outcome (buzón,
# notificaciones, banners, creación de conversación, REFER de transferencia) es
# responsabilidad del consumidor (controller `/sip/*` / InboundCallBuilder).
#
# Para cambiar/desactivar/reordenar una regla: editar la lista RULES (DEX-1).
# NOTA: el plan §17.2 ubica `SharedNumberRule` (R3-1) tras WorkingHoursRule; no
# está incluida aquí todavía (pendiente de confirmación).
class Sip::RoutingDecisionService
  RULES = [
    Sip::Routing::Rules::WorkingHoursRule,
    Sip::Routing::Rules::AssignedAgentRule,
    Sip::Routing::Rules::TeamRoundRobinRule,
    Sip::Routing::Rules::QueueLimitRule,
    Sip::Routing::Rules::VoicemailFallbackRule
  ].freeze

  attr_reader :context

  def self.call(context)
    new(context).call
  end

  def initialize(context)
    @context = context
  end

  def call
    RULES.each do |rule_class|
      return @context if rule_class.new.call(@context) == :handled
    end
    @context
  end
end

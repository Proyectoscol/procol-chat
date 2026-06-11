module Sip
  module Routing
    # Estado que viaja por el pipeline de reglas (Sip::RoutingDecisionService).
    # Cada regla LEE del contexto y, si decide, escribe el resultado con resolve!.
    #
    # Un contexto vacío (sin inbox ni llamada) es válido y esperado: ninguna regla
    # aplica y el pipeline cae limpio hasta VoicemailFallbackRule (fallback seguro).
    class Context
      attr_reader :inbox, :from_number, :to_number
      attr_accessor :contact, :assigned_agent, :extension, :team, :shared_number, :outcome

      def initialize(inbox: nil, from_number: nil, to_number: nil, contact: nil,
                     assigned_agent: nil, team: nil)
        @inbox = inbox
        @from_number = from_number
        @to_number = to_number
        @contact = contact
        @assigned_agent = assigned_agent
        @team = team
        @shared_number = false
        @outcome = nil
      end

      def account
        inbox&.account
      end

      def channel
        inbox&.channel
      end

      # Config tunable del Channel::Voice (shared_numbers, max_queue_size, staging,
      # absence_threshold_days, enable_callback). Vacío si aún no hay canal de Voz.
      def config
        cfg = channel.respond_to?(:provider_config) ? channel.provider_config : nil
        (cfg || {}).with_indifferent_access
      end

      # Registra la decisión final del pipeline. La ejecución de los efectos
      # (buzón, notificaciones, banners, creación de conversación) es del consumidor.
      def resolve!(action, **data)
        @outcome = { action: action }.merge(data)
      end

      def resolved?
        !@outcome.nil?
      end
    end
  end
end

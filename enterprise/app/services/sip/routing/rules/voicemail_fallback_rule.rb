module Sip
  module Routing
    module Rules
      # Última regla del pipeline: SIEMPRE resuelve. Garantiza cero llamada perdida
      # silenciosa → buzón/callback + se crea conversación (la ejecución del efecto
      # es del consumidor del outcome). Es el fallback seguro del árbol de routing.
      class VoicemailFallbackRule
        def call(ctx)
          ctx.resolve!(:voicemail, agent: ctx.assigned_agent)
          :handled
        end
      end
    end
  end
end

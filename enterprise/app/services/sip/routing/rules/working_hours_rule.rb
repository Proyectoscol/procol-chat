module Sip
  module Routing
    module Rules
      # R4-1: fuera del horario laboral del inbox de Voz (America/Bogota) → buzón
      # + se notifica al asignado. Sin working_hours configurado el inbox responde
      # working_now? = true → 24/7 (fallback seguro), así que la regla continúa.
      class WorkingHoursRule
        def call(ctx)
          inbox = ctx.inbox
          return :continue unless inbox.respond_to?(:out_of_office?)
          return :continue unless inbox.out_of_office?

          ctx.resolve!(:after_hours, agent: ctx.assigned_agent)
          :handled
        end
      end
    end
  end
end

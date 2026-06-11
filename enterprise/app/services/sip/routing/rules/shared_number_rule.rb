module Sip
  module Routing
    module Rules
      # R3-1: número compartido / conmutador. Cuando el número que llama es un
      # conmutador de empresa declarado en config.shared_numbers, o lo comparten
      # varios contactos (dueño ambiguo), NO existe un único asesor asignado: la
      # llamada debe saltar el match de contacto e ir al IVR/Team.
      #
      # Esta regla NUNCA cierra el pipeline: marca ctx.shared_number = true y
      # continúa. AssignedAgentRule respeta el flag y cede (→ TeamRoundRobin/IVR).
      class SharedNumberRule
        def call(ctx)
          return :continue unless ctx.inbox && ctx.from_number
          return :continue unless shared?(ctx)

          ctx.shared_number = true
          :continue
        end

        private

        def shared?(ctx)
          e164 = Sip::CallRoutingService.normalize_e164(ctx.from_number)
          return false if e164.blank?

          configured?(ctx, e164) || multiple_contacts?(ctx, e164)
        end

        # Conmutador declarado por el admin en la config del Channel::Voice.
        def configured?(ctx, e164)
          Array(ctx.config[:shared_numbers])
            .map { |n| Sip::CallRoutingService.normalize_e164(n) }
            .include?(e164)
        end

        # Dueño ambiguo: el mismo número de teléfono vive en >1 contacto de la cuenta.
        def multiple_contacts?(ctx, e164)
          ctx.account.contacts.where(phone_number: e164).limit(2).count > 1
        end
      end
    end
  end
end

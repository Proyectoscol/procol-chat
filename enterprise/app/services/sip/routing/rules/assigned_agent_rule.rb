module Sip
  module Routing
    module Rules
      # Asesor "dueño" del contacto (R4-3 / R3-3). Resuelve el asignado reusando
      # Sip::CallRoutingService y decide según su estado:
      #   Caso A — presente y disponible (SIP online ∩ Chatwoot online) → suena solo a él.
      #   Caso B — ocupado (en Call.active o Chatwoot 'busy')            → callback, NO redirige.
      #   Caso C — ausente:
      #            corta (< absence_threshold_days)  → callback, NO redirige.
      #            larga (> umbral o sip_absence_mode) → setea ctx.team y CONTINÚA al RR del Team.
      #
      # Sin contacto asignado (CallRoutingService → ivr) → continúa (IVR/Team RR).
      class AssignedAgentRule
        def call(ctx)
          return :continue unless ctx.inbox && ctx.from_number
          # Número compartido/conmutador (R3-1): sin dueño único → cede al IVR/Team.
          return :continue if ctx.shared_number

          routing = Sip::CallRoutingService.call(inbox: ctx.inbox, from_number: ctx.from_number)
          return :continue if routing[:action] == 'ivr'

          agent = routing[:agent]
          ctx.assigned_agent = agent
          ctx.extension = routing[:extension]
          identity = sip_identity(ctx, agent)

          return busy(ctx, agent) if busy?(ctx, agent)
          return ring(ctx, agent) if available?(ctx, agent, identity)

          absent(ctx, agent, identity)
        end

        private

        def sip_identity(ctx, agent)
          SipIdentity.find_by(account_id: ctx.account.id, user_id: agent.id)
        end

        # Caso B: una llamada activa aceptada por el asesor, o disponibilidad 'busy'.
        def busy?(ctx, agent)
          return true if chatwoot_status(ctx, agent) == 'busy'

          Call.active.where(account_id: ctx.account.id, accepted_by_agent_id: agent.id).exists?
        end

        # Caso A: registrado en SIP (algún dispositivo) y disponible en Chatwoot.
        def available?(ctx, agent, identity)
          identity&.online? && chatwoot_status(ctx, agent) == 'online'
        end

        def chatwoot_status(ctx, agent)
          OnlineStatusTracker.get_status(ctx.account.id, agent.id)
        end

        def busy(ctx, agent)
          ctx.resolve!(:busy_callback, agent: agent)
          :handled
        end

        def ring(ctx, agent)
          ctx.resolve!(:ring_agent, agent: agent, extension: ctx.extension)
          :handled
        end

        # Caso C. Ausencia larga (o modo ausente admin) → cede al RR del Team del
        # ausente. Ausencia corta → callback sin redirigir.
        def absent(ctx, agent, identity)
          if absent_long?(ctx, identity)
            ctx.team = agent_team(ctx, agent)
            return :continue
          end

          ctx.resolve!(:absent_callback, agent: agent)
          :handled
        end

        # Aproximación por días calendario. El cálculo fino en días LABORABLES
        # (festivos colombianos incl.) es de Sip::AbsenceDetectorJob (§14.2).
        def absent_long?(ctx, identity)
          return true if identity.nil? || identity.sip_absence_mode
          return true if identity.sip_last_registered_at.blank?

          threshold = (ctx.config[:absence_threshold_days] || 2).to_i
          (Time.zone.now - identity.sip_last_registered_at) > threshold.days
        end

        def agent_team(ctx, agent)
          Team.joins(:team_members)
              .where(account_id: ctx.account.id, team_members: { user_id: agent.id })
              .first
        end
      end
    end
  end
end

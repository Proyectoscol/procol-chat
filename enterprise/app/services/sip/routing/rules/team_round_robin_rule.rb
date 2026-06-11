module Sip
  module Routing
    module Rules
      # Round-robin del Team (lo setea IVR dígito→Team o la ausencia larga del
      # AssignedAgentRule). Elige a quién SUENA (efímero, §1): la conversación se
      # asigna recién en el evento ARI `answered` (FIX-4), no aquí.
      #
      # allowed_agent_ids = miembros del Team ∩ inbox-members de Voz ∩ SIP online
      #                     (sip_active_contacts > 0) ∩ Chatwoot online − Call.active.
      #
      # Selección ATÓMICA (UPDATE ... RETURNING sobre FOR UPDATE SKIP LOCKED): dos
      # llamadas simultáneas del mismo Team nunca eligen al mismo asesor (§6). El
      # ORDER BY last_rung_at + el bump de last_rung_at en la fila elegida implementan
      # la rotación (el recién sonado pasa al final de la cola). NULLS FIRST: un asesor
      # que nunca ha sonado tiene prioridad.
      class TeamRoundRobinRule
        def call(ctx)
          return :continue unless ctx.team && ctx.inbox

          ids = allowed_agent_ids(ctx)
          return :continue if ids.empty?

          row = claim_next_identity(ctx.account.id, ids)
          return :continue if row.nil?

          ctx.resolve!(:team_ring, agent_id: row['user_id'], extension: row['sip_extension'])
          :handled
        end

        private

        def allowed_agent_ids(ctx)
          account_id = ctx.account.id
          team_ids = ctx.team.members.pluck(:id)
          inbox_ids = ctx.inbox.inbox_members.pluck(:user_id)
          online_ids = OnlineStatusTracker.get_available_user_ids(account_id).map(&:to_i)
          busy_ids = Call.active.where(account_id: account_id).pluck(:accepted_by_agent_id).compact

          ((team_ids & inbox_ids & online_ids) - busy_ids).map(&:to_i)
        end

        # IDs son enteros (user_ids/account_id) → seguros para interpolar.
        def claim_next_identity(account_id, user_ids)
          sql = <<~SQL.squish
            UPDATE sip_identities
            SET last_rung_at = NOW()
            WHERE id = (
              SELECT id FROM sip_identities
              WHERE account_id = #{account_id.to_i}
                AND user_id IN (#{user_ids.map(&:to_i).join(',')})
                AND sip_active_contacts > 0
              ORDER BY last_rung_at ASC NULLS FIRST
              FOR UPDATE SKIP LOCKED
              LIMIT 1
            )
            RETURNING user_id, sip_extension
          SQL
          SipIdentity.connection.exec_query(sql).first
        end
      end
    end
  end
end

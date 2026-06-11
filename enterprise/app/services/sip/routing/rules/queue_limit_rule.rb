module Sip
  module Routing
    module Rules
      # R4-2: si la cola del inbox de Voz supera max_queue_size (config del canal,
      # default 10) → rechazo + conversación "llamada rechazada por cola llena".
      # La cola = llamadas activas aún sonando (sin asesor que haya contestado).
      class QueueLimitRule
        DEFAULT_MAX_QUEUE_SIZE = 10

        def call(ctx)
          return :continue unless ctx.inbox

          max = (ctx.config[:max_queue_size] || DEFAULT_MAX_QUEUE_SIZE).to_i
          queued = Call.active
                       .where(account_id: ctx.account.id, inbox_id: ctx.inbox.id, status: 'ringing')
                       .count
          return :continue if queued < max

          ctx.resolve!(:queue_rejected, queue_size: queued, max: max)
          :handled
        end
      end
    end
  end
end

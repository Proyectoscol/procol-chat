# Seguimiento de progreso de una corrida manual del pipeline diario (ver
# Api::V1::Accounts::Auditoria::DailyJobsController) -- mismo espiritu que
# el Redis::Alfred + TTL que ya usa Auditoria::ConversationAnalyzerJob para
# una sola conversacion (pending_key/error_key), extendido a una corrida
# masiva de muchas conversaciones/asesores. No usa una tabla nueva a
# proposito: es estado efimero de "como va la corrida ahora mismo", no un
# historial que deba sobrevivir mas alla de la pestaña del admin.
class Auditoria::PipelineRunTracker
  TTL = 6.hours

  def self.start!(account, kind, total:)
    state = { status: 'running', total: total, processed: 0, errored: 0, spend_limited: false, started_at: Time.current.to_i }
    Redis::Alfred.set(key(account, kind), state.to_json, ex: TTL)
  end

  def self.increment_processed!(account, kind)
    update!(account, kind) { |state| state['processed'] += 1 }
  end

  def self.increment_errored!(account, kind, spend_limited: false)
    update!(account, kind) do |state|
      state['errored'] += 1
      state['spend_limited'] ||= spend_limited
    end
  end

  def self.status(account, kind)
    raw = Redis::Alfred.get(key(account, kind))
    return { status: 'idle' } if raw.blank?

    state = JSON.parse(raw)
    state['status'] = 'completed' if state['processed'] + state['errored'] >= state['total']
    state
  end

  # GET+SET, no atomico, a proposito -- el volumen esperado (decenas/cientos
  # de conversaciones, nunca miles en paralelo real dado el escalonado de 1s
  # entre jobs en los schedulers) hace el riesgo de condicion de carrera
  # insignificante frente a la complejidad de montar un lock distribuido
  # nuevo solo para un contador informativo, no critico para el gasto real
  # (el limite de gasto real lo sigue aplicando Auditoria::AiUsageLogger de
  # forma independiente, este tracker nunca decide si gastar o no).
  def self.update!(account, kind)
    raw = Redis::Alfred.get(key(account, kind))
    return if raw.blank?

    state = JSON.parse(raw)
    yield state
    Redis::Alfred.set(key(account, kind), state.to_json, ex: TTL)
  end
  private_class_method :update!

  def self.key(account, kind)
    format(Redis::RedisKeys::AUDITORIA_PIPELINE_RUN, account_id: account.id, kind: kind)
  end
  private_class_method :key
end

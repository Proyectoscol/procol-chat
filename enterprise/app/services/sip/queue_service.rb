# Contador de cola de llamadas entrantes en Redis (pre-check rápido antes del DB
# round-trip del QueueLimitRule). La fuente autoritativa sigue siendo la BD; este
# contador evita la query en el camino caliente del routing.
#
# Ciclo de vida por llamada:
#   routing#routing devuelve 'dial'  → increment(inbox_id)
#   events#events recibe 'answered'  → decrement(inbox_id)  (se atendió)
#   events#events recibe 'ended'/'no_answer' → decrement(inbox_id)
#
# El contador nunca va negativo (floor 0). No tiene TTL: si el proceso Stasis
# muere con llamadas activas el contador queda desfasado. Reconciliar en
# SipPresenceService#sync o vía QueueLimitRule (DB) como fallback.
class Sip::QueueService
  KEY_PREFIX = 'sip:queue'
  DEFAULT_MAX = 10

  def self.increment(inbox_id)
    $alfred.with { |r| r.incr(key(inbox_id)) }
  end

  def self.decrement(inbox_id)
    $alfred.with do |r|
      val = r.decr(key(inbox_id))
      r.set(key(inbox_id), 0) if val.negative?
      [val, 0].max
    end
  end

  def self.count(inbox_id)
    $alfred.with { |r| r.get(key(inbox_id)).to_i }
  end

  # true si la cola del inbox ya alcanzó el máximo configurado.
  def self.full?(inbox_id, max: DEFAULT_MAX)
    count(inbox_id) >= max
  end

  def self.reset(inbox_id)
    $alfred.with { |r| r.set(key(inbox_id), 0) }
  end

  private_class_method def self.key(inbox_id)
    "#{KEY_PREFIX}:#{inbox_id}"
  end
end

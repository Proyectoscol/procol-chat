# Traduce los eventos de estado que la app Stasis (ARI) envía por POST /sip/events
# a los estados que entiende Voice::CallStatus::Manager (FIX-9 del plan). Es el
# gemelo de Voice::StatusUpdateService, pero filtra provider: :asterisk en vez de
# :twilio y usa ASTERISK_STATUS_MAP en vez de TWILIO_STATUS_MAP.
#
# Acepta tanto los estados semánticos que normaliza Stasis (ringing/in_progress/…)
# como los tokens crudos de ARI (Up, Hangup, StasisStart) como alias.
#
# NOTA (FIX-9): Call NO tiene estado 'busy' (Call::STATUSES = ringing, in_progress,
# completed, no_answer, failed). Un BUSY de Asterisk (hangup cause=17) se mapea a
# 'no_answer', igual que hace TWILIO_STATUS_MAP. La granularidad de causas ARI
# (16=completed, 17/19/21=no_answer, otras=failed) la resuelve la app Stasis antes
# de POSTear el estado semántico.
class Sip::StatusUpdateService
  pattr_initialize [:account!, :call_sid!, :call_status, { payload: {} }]

  ASTERISK_STATUS_MAP = {
    'ringing' => 'ringing',
    'ring' => 'ringing',
    'stasisstart' => 'ringing',
    'in_progress' => 'in_progress',
    'up' => 'in_progress',
    'answered' => 'in_progress',
    'completed' => 'completed',
    'hangup' => 'completed',
    'no_answer' => 'no_answer',
    'noanswer' => 'no_answer',
    'busy' => 'no_answer',
    'failed' => 'failed'
  }.freeze

  def perform
    normalized_status = normalize_status(call_status)
    return if normalized_status.blank?

    call = Call.where(account_id: account.id).find_by(provider: :asterisk, provider_call_id: call_sid)
    return unless call

    Voice::CallStatus::Manager.new(call: call).process_status_update(
      normalized_status,
      duration: payload_duration,
      timestamp: payload_timestamp
    )
  end

  private

  def normalize_status(status)
    return if status.to_s.strip.empty?

    ASTERISK_STATUS_MAP[status.to_s.strip.downcase]
  end

  def payload_duration
    return unless payload.is_a?(Hash)

    duration = payload['duration'] || payload['CallDuration'] || payload['call_duration']
    duration&.to_i
  end

  def payload_timestamp
    return unless payload.is_a?(Hash)

    ts = payload['timestamp'] || payload['Timestamp']
    return unless ts

    Time.zone.parse(ts.to_s).to_i
  rescue ArgumentError
    nil
  end
end

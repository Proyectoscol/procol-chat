# Endpoints internos server-to-server consumidos por la app Stasis (VPS-2) — ENG-3.
#   GET  /api/v1/internal/sip/routing  → pipeline completo de routing
#   POST /api/v1/internal/sip/events   → presencia SIP y ciclo de vida de llamadas
#
# Seguridad:
#   1. Token en header X-Sip-Token (secure_compare, tiempo constante).
#   2. CSRF exento (ApplicationController ya lo hace).
#   3. IP allowlist del VPS-2 (SIP_ALLOWED_IPS); fail-closed en producción.
#   4. Throttle 60 req/min por IP en config/initializers/rack_attack.rb.
# Token inválido/ausente → 401 sin revelar el motivo.
class Sip::InternalController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :authenticate_sip_request!

  # GET /api/v1/internal/sip/routing
  # Params (Stasis app):
  #   phone      — número llamante en E164 (+57...)
  #   to         — DID llamado en E164 (channel.dialplan.exten normalizado)
  #   ivr_digit  — dígito DTMF elegido en IVR (segunda llamada del ciclo)
  #   linkedid   — ID estable de la llamada (para trazabilidad)
  #
  # Respuesta al formato que Stasis espera:
  #   { action: 'dial',      extension: '1001' }
  #   { action: 'ivr',       prompt: 'ivr-ciudades' }
  #   { action: 'voicemail' }
  #   { action: 'busy',      reason: 'queue_full' | nil }
  def routing
    inbox = resolve_voice_inbox
    return head(:not_found) unless inbox

    # Pre-check rápido vía Redis antes del pipeline completo (~1 ms vs ~50 ms).
    if Sip::QueueService.full?(inbox.id, max: queue_max(inbox))
      return render json: { action: 'busy', reason: 'queue_full' }
    end

    result = params[:ivr_digit].present? ? route_ivr(inbox) : route_call(inbox)

    # Incrementar cola solo cuando vamos a hacer sonar un teléfono.
    Sip::QueueService.increment(inbox.id) if result[:action] == 'dial'

    render json: result
  end

  # POST /api/v1/internal/sip/events
  # Acepta tanto event_type (Stasis app) como type (legado).
  def events
    event_type = (params[:event_type].presence || params[:type]).to_s
    return render json: { error: 'unknown event type' }, status: :unprocessable_content if event_type.blank?
    return head(:not_found) unless current_account

    case event_type
    when 'sip_register', 'register'
      presence_service.register(params[:extension])
    when 'sip_unregister', 'unregister'
      presence_service.unregister(params[:extension])
    when 'sync'
      presence_service.sync(params[:registered])
    when 'answered'
      handle_call_answered
    when 'ended'
      handle_call_ended
    when 'no_answer'
      handle_call_no_answer
    when 'call_status'
      handle_call_status_event
    else
      return render json: { error: 'unknown event type' }, status: :unprocessable_content
    end

    head :no_content
  end

  private

  # --- routing helpers ---

  def route_call(inbox)
    ctx = Sip::Routing::Context.new(
      inbox: inbox,
      from_number: params[:phone],
      to_number: params[:to]
    )
    Sip::RoutingDecisionService.call(ctx)
    outcome_to_stasis(ctx.outcome, inbox)
  end

  def route_ivr(inbox)
    team = Sip::IvrRoutingService.call(inbox: inbox, digit: params[:ivr_digit])
    return { action: 'voicemail' } unless team

    ctx = Sip::Routing::Context.new(inbox: inbox, team: team)
    Sip::Routing::Rules::TeamRoundRobinRule.new.call(ctx)
    outcome_to_stasis(ctx.outcome, inbox)
  end

  # Traduce el outcome interno del pipeline de reglas al formato que la Stasis
  # app de Node espera. Solo los actions que Stasis conoce salen aquí.
  def outcome_to_stasis(outcome, inbox)
    return { action: 'ivr', prompt: ivr_prompt(inbox) } unless outcome

    case outcome[:action]
    when :ring_agent, :team_ring
      { action: 'dial', extension: outcome[:extension].to_s }
    when :busy_callback
      { action: 'busy' }
    when :absent_callback
      { action: 'ivr', prompt: ivr_prompt(inbox) }
    when :after_hours, :voicemail
      { action: 'voicemail' }
    when :queue_rejected
      { action: 'busy', reason: 'queue_full' }
    else
      { action: 'ivr', prompt: ivr_prompt(inbox) }
    end
  end

  def ivr_prompt(inbox)
    channel = inbox.channel
    cfg = channel.respond_to?(:provider_config) ? channel.provider_config || {} : {}
    cfg.with_indifferent_access[:ivr_prompt].presence || 'ivr-ciudades'
  end

  def queue_max(inbox)
    channel = inbox.channel
    cfg = channel.respond_to?(:provider_config) ? channel.provider_config || {} : {}
    (cfg.with_indifferent_access[:max_queue_size] || Sip::QueueService::DEFAULT_MAX).to_i
  end

  # --- events helpers ---

  def handle_call_answered
    inbox = resolve_voice_inbox
    Sip::QueueService.decrement(inbox.id) if inbox
  end

  def handle_call_ended
    inbox = resolve_voice_inbox
    return unless inbox

    Sip::QueueService.decrement(inbox.id)

    stasis_payload = params.permit(:event_type, :from_number, :to, :linkedid,
                                   :duration_seconds, :call_direction, :cause).to_h
    return if stasis_payload[:from_number].blank? || stasis_payload[:linkedid].blank?

    Sip::AsteriskCallLogger.call(inbox: inbox, payload: stasis_payload)
    Voice::TimelineMirrorService.perform(stasis_payload)
  end

  def handle_call_no_answer
    inbox = resolve_voice_inbox
    return unless inbox

    Sip::QueueService.decrement(inbox.id)

    stasis_payload = params.permit(:event_type, :from_number, :to, :linkedid,
                                   :call_direction).to_h
    return if stasis_payload[:from_number].blank? || stasis_payload[:linkedid].blank?

    Sip::AsteriskCallLogger.call(inbox: inbox, payload: stasis_payload)
    Voice::TimelineMirrorService.perform(stasis_payload)
  end

  def handle_call_status_event
    Sip::StatusUpdateService.new(
      account: current_account,
      call_sid: params[:call_sid],
      call_status: params[:status],
      payload: params.to_unsafe_h
    ).perform
  end

  def presence_service
    @presence_service ||= Sip::PresenceService.new(account: current_account)
  end

  # --- inbox / auth ---

  # DID (to) → Channel::Voice → inbox de Voz. Normaliza E164 igual que el caller.
  def resolve_voice_inbox
    did = Sip::CallRoutingService.normalize_e164(params[:to])
    return nil if did.blank?

    Channel::Voice.find_by(phone_number: did)&.inbox
  end

  def current_account
    @current_account ||= Account.find_by(id: params[:account_id])
  end

  def authenticate_sip_request!
    head :unauthorized unless allowed_ip? && valid_token?
  end

  def valid_token?
    expected = ENV.fetch('SIP_INTERNAL_TOKEN', nil)
    provided = request.headers['X-Sip-Token']
    return false if expected.blank? || provided.blank?

    ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end

  # Allowlist del VPS-2. En PRODUCCIÓN setear SIP_ALLOWED_IPS con la(s) IP(s)
  # pública(s) del VPS-2 separadas por coma. Sin la variable: fail-closed en
  # producción (bloquea), allow-all en dev/test.
  def allowed_ip?
    allowed = ENV.fetch('SIP_ALLOWED_IPS', '').split(',').map(&:strip).reject(&:blank?)
    if allowed.empty?
      if Rails.env.production?
        Rails.logger.error '[SIP] SIP_ALLOWED_IPS not set in production — blocking request (fail-closed)'
        return false
      end
      return true
    end

    allowed.include?(request.remote_ip)
  end
end

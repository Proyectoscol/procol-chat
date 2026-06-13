# Endpoints internos server-to-server consumidos por la app Stasis (VPS-2) — ENG-3.
#   GET  /api/v1/internal/sip/routing  → Sip::CallRoutingService (dígito de routing)
#   POST /api/v1/internal/sip/events   → según `type`: presencia o estado de llamada
#
# Seguridad (el POST crea/muta datos → el token da integridad):
#   1. Token en header X-Sip-Token comparado con secure_compare (tiempo constante).
#   2. CSRF exento (ApplicationController ya lo hace; explícito por claridad).
#   3. IP allowlist del VPS-2 (SIP_ALLOWED_IPS); opcional en dev si no está seteado.
#   4. Throttle 60 req/min por IP en config/initializers/rack_attack.rb.
# Token inválido/ausente → 401 sin revelar el motivo.
class Sip::InternalController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :authenticate_sip_request!

  def routing
    inbox = resolve_voice_inbox
    return head(:not_found) unless inbox

    render json: Sip::CallRoutingService.call(inbox: inbox, from_number: params[:from])
  end

  def events
    case params[:type].to_s
    when 'register', 'unregister', 'sync'
      return head(:not_found) unless current_account

      handle_presence_event
    when 'call_status'
      return head(:not_found) unless current_account

      handle_call_status_event
    else
      return render json: { error: 'unknown event type' }, status: :unprocessable_content
    end

    head :no_content
  end

  private

  def handle_presence_event
    service = Sip::PresenceService.new(account: current_account)
    case params[:type].to_s
    when 'register'   then service.register(params[:extension])
    when 'unregister' then service.unregister(params[:extension])
    when 'sync'       then service.sync(params[:registered])
    end
  end

  def handle_call_status_event
    Sip::StatusUpdateService.new(
      account: current_account,
      call_sid: params[:call_sid],
      call_status: params[:status],
      payload: params.to_unsafe_h
    ).perform
  end

  # DID (to) → Channel::Voice de la cuenta → inbox de Voz. Reusa la normalización E164.
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

# Entrega al frontend las credenciales SIP para que JsSIP haga el REGISTER
# (lo consume GET /sip/credential, auth de sesión normal — §3 línea 135).
#
# v1 (FIX-11 → U2): secret ESTÁTICO por extensión, guardado encriptado en reposo
# (sip_identities.sip_password) y entregado al propio asesor (visible en sus
# DevTools; riesgo acotado). Credencial efímera con TTL + invalidación en logout
# → fase 2 (evita PJSIP-realtime ahora).
#
# Multi-cliente: la SipIdentity es por (account_id, user_id); se scopea a la cuenta.
class Sip::CredentialService
  WSS_DEFAULT_PORT = '8089'

  attr_reader :user, :account

  def self.call(user:, account:)
    new(user: user, account: account).call
  end

  def initialize(user:, account:)
    @user = user
    @account = account
  end

  # @return [Hash, nil] credenciales del REGISTER de JsSIP, o nil si el usuario no
  #   tiene SipIdentity en la cuenta.
  def call
    identity = SipIdentity.find_by(account_id: account.id, user_id: user.id)
    return nil unless identity

    {
      sip_extension: identity.sip_extension,
      sip_password: identity.sip_password,
      wss_url: wss_url,
      sip_domain: sip_host,
      ice_servers: Call.default_ice_servers
    }
  end

  private

  def wss_url
    return nil if sip_host.blank?

    "wss://#{sip_host}:#{ENV.fetch('SIP_WSS_PORT', WSS_DEFAULT_PORT)}/ws"
  end

  # Host del Asterisk/FreePBX (registrar SIP y servidor WSS). §9: SIP_WSS_HOST/PORT.
  def sip_host
    ENV.fetch('SIP_WSS_HOST', nil)
  end
end

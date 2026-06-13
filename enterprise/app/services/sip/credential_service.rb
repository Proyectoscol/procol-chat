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
  #
  # sip_extension/sip_password salen de la SipIdentity (por asesor). wss_url y
  # sip_domain son CONFIG GLOBAL del servidor (ENV SIP_WSS_HOST/PORT), NO columnas
  # de sip_identities — se construyen dinámicamente, sin tocar la BD.
  def call
    identity = SipIdentity.find_by(account_id: account.id, user_id: user.id)
    return nil unless identity

    {
      sip_extension: identity.sip_extension,
      sip_password: identity.sip_password,
      wss_url: wss_url,
      sip_domain: ENV.fetch('SIP_WSS_HOST', nil),
      ice_servers: ice_servers
    }
  end

  private

  def ice_servers
    servers = Call.default_ice_servers.dup
    turn_user = ENV.fetch('TURN_USERNAME', nil)
    turn_cred = ENV.fetch('TURN_CREDENTIAL', nil)
    turn_host = ENV.fetch('SIP_WSS_HOST', nil)
    if turn_host.present? && turn_user.present? && turn_cred.present?
      servers << {
        urls: ["turn:#{turn_host}:3478"],
        username: turn_user,
        credential: turn_cred
      }
    end
    servers
  end

  # nil si SIP_WSS_HOST no está configurado → register() falla silenciosamente
  # (comportamiento correcto en dev sin FreePBX).
  def wss_url
    host = ENV.fetch('SIP_WSS_HOST', nil)
    return nil if host.blank?

    "wss://#{host}:#{ENV.fetch('SIP_WSS_PORT', '8089')}/ws"
  end
end

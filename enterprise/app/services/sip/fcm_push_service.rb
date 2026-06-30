# Envía un FCM data push al dispositivo Android del agente cuando Asterisk
# detecta una llamada entrante (evento Newchannel en AMI).
# Usa la gem fcm (send_v1) igual que Notification::PushNotificationService.
# Credenciales separadas del Firebase de Chatwoot web: SIP_FIREBASE_PROJECT_ID
# y SIP_FIREBASE_CREDENTIALS (JSON del service account).
class Sip::FcmPushService
  def self.send_incoming_call(identity:, caller_id:, caller_name:)
    new(identity: identity, caller_id: caller_id, caller_name: caller_name).call
  end

  def initialize(identity:, caller_id:, caller_name:)
    @identity    = identity
    @caller_id   = caller_id.to_s
    @caller_name = caller_name.to_s
  end

  def call
    return send_fcm if @identity.sip_fcm_token.present?

    Rails.logger.warn("[Sip::FcmPushService] user_id=#{@identity.user_id} no tiene sip_fcm_token")
    false
  end

  private

  def send_fcm
    project_id   = ENV.fetch('SIP_FIREBASE_PROJECT_ID', nil)
    credentials  = ENV.fetch('SIP_FIREBASE_CREDENTIALS', nil)

    unless project_id.present? && credentials.present?
      Rails.logger.warn('[Sip::FcmPushService] SIP_FIREBASE_PROJECT_ID / SIP_FIREBASE_CREDENTIALS no configurados')
      return false
    end

    fcm_service = Notification::FcmService.new(project_id, credentials)
    response    = fcm_service.fcm_client.send_v1(fcm_payload)

    Rails.logger.info("[Sip::FcmPushService] user_id=#{@identity.user_id} response=#{response.inspect}")
    response[:status_code] == 200
  rescue StandardError => e
    Rails.logger.error("[Sip::FcmPushService] Error: #{e.message}")
    false
  end

  def fcm_payload
    {
      token: @identity.sip_fcm_token,
      data: {
        type: 'sip_incoming_call',
        caller_id: @caller_id,
        caller_name: @caller_name
      },
      android: { priority: 'high' }
      # Sin clave :notification — data-only para que Android despierte la app cerrada
    }
  end
end

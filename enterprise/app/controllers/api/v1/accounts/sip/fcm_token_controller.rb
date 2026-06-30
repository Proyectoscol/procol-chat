# POST /api/v1/accounts/:account_id/sip/fcm_token
# El asesor actualiza su propio token de push (FCM Android o APNs iOS).
# Se llama automáticamente desde la app móvil después de cada login/registro SIP.
class Api::V1::Accounts::Sip::FcmTokenController < Api::V1::Accounts::BaseController
  def create
    identity = SipIdentity.find_by(account: Current.account, user: Current.user)
    return render json: { error: 'SIP identity not found' }, status: :not_found if identity.nil?

    platform = params.fetch(:platform, 'android')
    if platform == 'ios'
      identity.update!(sip_apns_voip_token: params.require(:token), sip_push_token_updated_at: Time.current)
    else
      identity.update!(sip_fcm_token: params.require(:token), sip_push_token_updated_at: Time.current)
    end

    head :ok
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end

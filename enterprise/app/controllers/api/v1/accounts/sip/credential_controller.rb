# GET /api/v1/accounts/:account_id/sip/credential
# Auth de sesión del asesor (token Chatwoot, heredada de Api::V1::Accounts::BaseController).
# Entrega al frontend la credencial SIP de SU propia SipIdentity para que JsSIP
# (useJsSipSession) haga el REGISTER. Sin SipIdentity → 404 con cuerpo vacío.
class Api::V1::Accounts::Sip::CredentialController < Api::V1::Accounts::BaseController
  def show
    credentials = Sip::CredentialService.call(user: Current.user, account: Current.account)
    return render json: {}, status: :not_found if credentials.nil?

    render json: credentials, status: :ok
  end
end

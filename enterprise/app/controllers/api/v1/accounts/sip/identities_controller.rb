# PATCH /api/v1/accounts/:account_id/sip/identities/:agent_id
# Solo administradores. Crea o actualiza la SipIdentity de un asesor en esta cuenta.
# Nunca devuelve sip_password.
class Api::V1::Accounts::Sip::IdentitiesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def update
    agent = Current.account.users.find(params[:agent_id])
    sip = SipIdentity.find_or_initialize_by(account: Current.account, user: agent)

    sip.sip_extension = identity_params[:sip_extension].strip if identity_params[:sip_extension].present?
    sip.sip_password = identity_params[:sip_password] if identity_params[:sip_password].present?

    unless identity_params[:sip_active].nil?
      sip.sip_absence_mode = !ActiveModel::Type::Boolean.new.cast(identity_params[:sip_active])
    end

    sip.save!

    render json: {
      agent_id: agent.id,
      sip_extension: sip.sip_extension,
      sip_active: !sip.sip_absence_mode,
      updated_at: sip.updated_at
    }, status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Agent not found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def identity_params
    params.permit(:sip_extension, :sip_password, :sip_active)
  end
end

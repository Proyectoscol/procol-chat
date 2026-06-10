# Identidad SIP de un asesor (extensión + presencia multi-dispositivo).
# Overlay enterprise del fork (aislado del rebase sobre upstream).
# Multi-cliente: única por (account_id, sip_extension) y (account_id, user_id).
class SipIdentity < ApplicationRecord
  belongs_to :account
  belongs_to :user

  # v1: secret estático encriptado en reposo. Llega al navegador para el REGISTER
  # de JsSIP (visible al propio asesor). Efímero/PJSIP-realtime → fase 2.
  encrypts :sip_password if Chatwoot.encryption_configured?

  validates :sip_extension, presence: true, uniqueness: { scope: :account_id }
  validates :user_id, uniqueness: { scope: :account_id }

  # Disponible para recibir llamadas si tiene al menos un dispositivo SIP
  # registrado (PC / Android / tablet). Reemplaza el antiguo sip_online booleano.
  def online?
    sip_active_contacts.to_i.positive?
  end
end

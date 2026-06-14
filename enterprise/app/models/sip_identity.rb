# Identidad SIP de un asesor (extensión + presencia multi-dispositivo).
# Overlay enterprise del fork (aislado del rebase sobre upstream).
# Multi-cliente: única por (account_id, sip_extension) y (account_id, user_id).
# == Schema Information
#
# Table name: sip_identities
#
#  id                        :bigint           not null, primary key
#  last_rung_at              :datetime
#  sip_absence_alerted_at    :datetime
#  sip_absence_mode          :boolean          default(FALSE), not null
#  sip_active_contacts       :integer          default(0), not null
#  sip_apns_voip_token       :string
#  sip_extension             :string           not null
#  sip_fcm_token             :string
#  sip_last_registered_at    :datetime
#  sip_password              :string
#  sip_push_token_updated_at :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  user_id                   :bigint           not null
#
# Indexes
#
#  index_sip_identities_on_account_id                    (account_id)
#  index_sip_identities_on_account_id_and_sip_extension  (account_id,sip_extension) UNIQUE
#  index_sip_identities_on_account_id_and_user_id        (account_id,user_id) UNIQUE
#  index_sip_identities_on_user_id                       (user_id)
#
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

  def inspect
    "#<SipIdentity id=#{id} sip_extension=#{sip_extension} [FILTERED]>"
  end
end

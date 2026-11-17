# Una fila = un cupo de control/consulta de seguimiento incluido en un
# procedimiento ya realizado (Service#included_sessions). available? dice si
# todavia se puede consumir; consume! lo liga a la cita de control que lo usa.
# == Schema Information
#
# Table name: calendario_contact_session_credits
#
#  id                         :bigint           not null, primary key
#  consumed_at                :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  consumed_by_appointment_id :bigint
#  contact_id                 :bigint           not null
#  granted_by_appointment_id  :bigint           not null
#
# Indexes
#
#  idx_on_consumed_by_appointment_id_bcc8214905              (consumed_by_appointment_id)
#  idx_on_granted_by_appointment_id_78ca1bf0dc               (granted_by_appointment_id)
#  index_calendario_contact_session_credits_on_account_id    (account_id)
#  index_calendario_contact_session_credits_on_contact_id    (contact_id)
#  index_calendario_session_credits_on_contact_and_consumed  (contact_id,consumed_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (consumed_by_appointment_id => calendario_appointments.id) ON DELETE => nullify
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (granted_by_appointment_id => calendario_appointments.id) ON DELETE => cascade
#
class Calendario::ContactSessionCredit < ApplicationRecord
  self.table_name = 'calendario_contact_session_credits'

  belongs_to :account
  belongs_to :contact
  belongs_to :granted_by_appointment, class_name: 'Calendario::Appointment'
  belongs_to :consumed_by_appointment, class_name: 'Calendario::Appointment', optional: true

  scope :available, -> { where(consumed_at: nil) }

  def available?
    consumed_at.blank?
  end

  def consume!(appointment)
    update!(consumed_at: Time.current, consumed_by_appointment: appointment)
  end
end

# Contacto esperando cupo para un profesional/servicio, sin fecha asignada
# todavia -- existe antes de que el doctor abra agenda. Se cumple (fulfilled)
# cuando se le crea una cita, o se reactiva (vuelve a pending) si esa cita se
# cancela de forma temporal (ver Calendario::WaitlistFulfillmentService).
# == Schema Information
#
# Table name: calendario_waitlist_entries
#
#  id                          :bigint           not null, primary key
#  notes                       :text
#  origin                      :integer          default("manual"), not null
#  status                      :integer          default("pending"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  contact_id                  :bigint           not null
#  fulfilled_by_appointment_id :bigint
#  professional_id             :bigint           not null
#  service_id                  :bigint           not null
#
# Indexes
#
#  idx_on_fulfilled_by_appointment_id_b9a15a3357             (fulfilled_by_appointment_id)
#  index_calendario_waitlist_entries_on_account_id           (account_id)
#  index_calendario_waitlist_entries_on_contact_id           (contact_id)
#  index_calendario_waitlist_entries_on_professional_id      (professional_id)
#  index_calendario_waitlist_entries_on_professional_status  (professional_id,status)
#  index_calendario_waitlist_entries_on_service_id           (service_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (fulfilled_by_appointment_id => calendario_appointments.id) ON DELETE => nullify
#  fk_rails_...  (professional_id => calendario_professionals.id) ON DELETE => cascade
#  fk_rails_...  (service_id => calendario_services.id) ON DELETE => cascade
#
class Calendario::WaitlistEntry < ApplicationRecord
  self.table_name = 'calendario_waitlist_entries'

  enum :status, { pending: 0, fulfilled: 1, cancelled: 2 }
  enum :origin, { manual: 0, cancellation: 1 }

  belongs_to :account
  belongs_to :contact
  belongs_to :professional, class_name: 'Calendario::Professional'
  belongs_to :service, class_name: 'Calendario::Service'
  belongs_to :fulfilled_by_appointment, class_name: 'Calendario::Appointment', optional: true

  validate :professional_belongs_to_account
  validate :contact_belongs_to_account

  scope :for_professional, ->(professional_id) { where(professional_id: professional_id) }

  private

  def professional_belongs_to_account
    return if professional.blank?
    return if professional.account_id == account_id

    errors.add(:professional, :invalid)
  end

  def contact_belongs_to_account
    return if contact.blank?
    return if contact.account_id == account_id

    errors.add(:contact, :invalid)
  end
end

# == Schema Information
#
# Table name: calendario_service_professionals
#
#  id                       :bigint           not null, primary key
#  eps_duration_minutes     :integer
#  private_duration_minutes :integer
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  professional_id          :bigint           not null
#  service_id               :bigint           not null
#
# Indexes
#
#  index_calendario_service_professionals_on_professional_id  (professional_id)
#  index_calendario_service_professionals_on_service_id       (service_id)
#  index_calendario_svc_profs_on_service_and_professional     (service_id,professional_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (professional_id => calendario_professionals.id) ON DELETE => cascade
#  fk_rails_...  (service_id => calendario_services.id) ON DELETE => cascade
#
class Calendario::ServiceProfessional < ApplicationRecord
  self.table_name = 'calendario_service_professionals'

  belongs_to :service, class_name: 'Calendario::Service'
  belongs_to :professional, class_name: 'Calendario::Professional'

  validates :professional_id, uniqueness: { scope: :service_id }
  validates :eps_duration_minutes, :private_duration_minutes,
            numericality: { only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 60 }, allow_nil: true
  validate :service_and_professional_same_account

  # Mismo patron que Calendario::Service#price_for -- duracion especifica
  # de este profesional para este servicio segun si el pagador es EPS o no
  # (particular/poliza/prepagada/plan_complementario, ver Calendario::Payer#kind).
  # nil si no se configuro override -- el caller cae al duration_minutes
  # fijo del servicio.
  def duration_minutes_for(payer)
    payer&.eps? ? eps_duration_minutes : private_duration_minutes
  end

  private

  def service_and_professional_same_account
    return if service.blank? || professional.blank?
    return if service.account_id == professional.account_id

    errors.add(:professional, :invalid)
  end
end

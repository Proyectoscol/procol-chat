# == Schema Information
#
# Table name: calendario_professionals
#
#  id           :bigint           not null, primary key
#  active       :boolean          default(TRUE), not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  specialty_id :bigint
#  user_id      :bigint
#
# Indexes
#
#  index_calendario_professionals_on_account_and_user  (account_id,user_id) UNIQUE
#  index_calendario_professionals_on_account_id        (account_id)
#  index_calendario_professionals_on_specialty_id      (specialty_id)
#  index_calendario_professionals_on_user_id           (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (specialty_id => calendario_specialties.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Calendario::Professional < ApplicationRecord
  self.table_name = 'calendario_professionals'

  belongs_to :account
  belongs_to :user, optional: true
  # optional: true a nivel de Rails/BD a proposito -- un profesional viejo
  # (de antes de este feature) puede quedar sin especialidad hasta que un
  # administrador la asigne. Para profesionales NUEVOS la exigencia real
  # vive en `validates :specialty, presence: true` de abajo.
  belongs_to :specialty, class_name: 'Calendario::Specialty', optional: true
  has_many :availabilities, class_name: 'Calendario::ProfessionalAvailability', dependent: :destroy
  has_many :service_professionals, class_name: 'Calendario::ServiceProfessional', dependent: :destroy
  has_many :services, through: :service_professionals, class_name: 'Calendario::Service'
  has_many :appointments, class_name: 'Calendario::Appointment', dependent: :destroy

  validates :name, presence: true
  validates :specialty, presence: true, on: :create
  validate :user_belongs_to_account
  validate :specialty_belongs_to_account

  scope :active, -> { where(active: true) }

  def self.find_or_create_from_agent(account:, user:)
    account.calendario_professionals.find_or_create_by!(user_id: user.id) do |professional|
      professional.name = user.name
    end
  end

  private

  def user_belongs_to_account
    return if user.blank?
    return if account.users.exists?(id: user_id)

    errors.add(:user, :invalid)
  end

  def specialty_belongs_to_account
    return if specialty.blank?
    return if specialty.account_id == account_id

    errors.add(:specialty, :invalid)
  end
end

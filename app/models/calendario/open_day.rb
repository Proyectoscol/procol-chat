# Marcador liviano de "el doctor abrio agenda para esta fecha" -- existe desde
# antes de que haya una sola cita. Sin esto no hay nada que listar entre que el
# doctor abre y que la asistente agenda la primera cita (ver design doc, Open
# Question 1).
# == Schema Information
#
# Table name: calendario_open_days
#
#  id              :bigint           not null, primary key
#  date            :date             not null
#  notes           :text
#  time_window     :integer          default("morning"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  opened_by_id    :bigint
#  professional_id :bigint           not null
#
# Indexes
#
#  index_calendario_open_days_on_account_id                (account_id)
#  index_calendario_open_days_on_opened_by_id              (opened_by_id)
#  index_calendario_open_days_on_professional_date_window  (professional_id,date,time_window)
#  index_calendario_open_days_on_professional_id           (professional_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (opened_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (professional_id => calendario_professionals.id) ON DELETE => cascade
#
class Calendario::OpenDay < ApplicationRecord
  self.table_name = 'calendario_open_days'

  enum :time_window, { morning: 0, afternoon: 1, full_day: 2 }

  belongs_to :account
  belongs_to :professional, class_name: 'Calendario::Professional'
  belongs_to :opened_by, class_name: 'User', optional: true

  validates :date, presence: true
  validate :professional_belongs_to_account

  scope :for_professional, ->(professional_id) { where(professional_id: professional_id) }

  # Advertencia, no bloqueo -- mismo criterio que AppointmentWarningsFinder: el
  # peor caso es una fila sobrante facil de borrar, no corrupcion de datos. Un
  # indice unico de BD bloquearia el caso real (dos ventanas distintas el
  # mismo dia), por eso esto vive aparte de las validaciones duras y lo
  # resuelve el booking service, no el modelo.
  def duplicate?
    return false if professional_id.blank? || date.blank?

    self.class.where(professional_id: professional_id, date: date, time_window: time_window)
        .where.not(id: id).exists?
  end

  private

  def professional_belongs_to_account
    return if professional.blank?
    return if professional.account_id == account_id

    errors.add(:professional, :invalid)
  end
end

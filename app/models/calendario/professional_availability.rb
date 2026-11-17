# == Schema Information
#
# Table name: calendario_professional_availabilities
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  end_time        :time             not null
#  ends_on         :date             not null
#  start_time      :time             not null
#  starts_on       :date             not null
#  weekdays        :integer          default([1, 2, 3, 4, 5]), not null, is an Array
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  professional_id :bigint           not null
#
# Indexes
#
#  idx_on_professional_id_d68050c101  (professional_id)
#
# Foreign Keys
#
#  fk_rails_...  (professional_id => calendario_professionals.id) ON DELETE => cascade
#
class Calendario::ProfessionalAvailability < ApplicationRecord
  self.table_name = 'calendario_professional_availabilities'

  include WeeklyAvailabilityWindow

  belongs_to :professional, class_name: 'Calendario::Professional'

  delegate :account, to: :professional

  private

  def availability_owner_id
    professional_id
  end

  def overlapping_window_scope
    self.class.where(professional_id: professional_id, active: true)
  end
end

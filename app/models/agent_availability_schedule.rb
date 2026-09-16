# == Schema Information
#
# Table name: agent_availability_schedules
#
#  id                :bigint           not null, primary key
#  active            :boolean          default(TRUE), not null
#  currently_locked  :boolean          default(FALSE), not null
#  end_time          :time             not null
#  ends_on           :date             not null
#  start_time        :time             not null
#  starts_on         :date             not null
#  weekdays          :integer          default([1, 2, 3, 4, 5]), not null, is an Array
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  created_by_id     :bigint
#  user_id           :bigint           not null
#
# Indexes
#
#  index_agent_availability_schedules_on_account_id          (account_id)
#  index_agent_availability_schedules_on_created_by_id       (created_by_id)
#  index_agent_availability_schedules_on_user_id             (user_id)
#  index_agent_availability_schedules_on_user_id_and_active  (user_id,active)
#

class AgentAvailabilitySchedule < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :created_by, class_name: 'User', optional: true

  validates :starts_on, :ends_on, :start_time, :end_time, presence: true
  validate :ends_on_not_before_starts_on
  validate :end_time_after_start_time
  validate :no_overlapping_schedule_for_user

  scope :active_today, lambda {
    today = Time.current.to_date
    where(active: true).where('starts_on <= ? AND ends_on >= ?', today, today)
  }

  def applies_on?(date)
    weekdays.include?(date.wday) && starts_on <= date && ends_on >= date
  end

  def in_window?(time)
    time_of_day = time.seconds_since_midnight
    time_of_day >= start_time.seconds_since_midnight && time_of_day < end_time.seconds_since_midnight
  end

  private

  def ends_on_not_before_starts_on
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, 'must be on or after starts_on')
  end

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank? || end_time > start_time

    errors.add(:end_time, 'must be after start_time')
  end

  def no_overlapping_schedule_for_user
    return if user_id.blank? || starts_on.blank? || ends_on.blank?

    overlapping = account.agent_availability_schedules
                         .where(user_id: user_id, active: true)
                         .where.not(id: id)
                         .where('starts_on <= ? AND ends_on >= ?', ends_on, starts_on)
                         .where('start_time < ? AND end_time > ?', end_time, start_time)

    errors.add(:base, 'overlaps with an existing schedule for this agent') if overlapping.exists?
  end
end

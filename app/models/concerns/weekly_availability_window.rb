module WeeklyAvailabilityWindow
  extend ActiveSupport::Concern

  included do
    validates :starts_on, :ends_on, :start_time, :end_time, presence: true
    validate :ends_on_not_before_starts_on
    validate :end_time_after_start_time
    validate :no_overlapping_window

    scope :active_today, lambda {
      today = Time.current.to_date
      where(active: true).where('starts_on <= ? AND ends_on >= ?', today, today)
    }
  end

  def applies_on?(date)
    weekdays.include?(date.wday) && starts_on <= date && ends_on >= date
  end

  def in_window?(time)
    time_of_day = time.seconds_since_midnight
    time_of_day >= start_time.seconds_since_midnight && time_of_day < end_time.seconds_since_midnight
  end

  # Unlike in_window? (a single instant, exclusive of end_time -- built for
  # "is this moment inside the shift"), this checks a whole span fits inside
  # the window, end_time inclusive -- a slot that ends exactly at closing time
  # is still valid. range_start/range_end must already be in the zone this
  # window's start_time/end_time are meant to represent (a bare `time` column
  # has no zone of its own).
  def covers?(range_start, range_end)
    return false unless applies_on?(range_start.to_date)
    return false unless range_start.to_date == range_end.to_date

    start_secs = range_start.seconds_since_midnight
    end_secs = range_end.seconds_since_midnight
    start_secs >= start_time.seconds_since_midnight && end_secs <= end_time.seconds_since_midnight
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

  # Including class must define #availability_owner_id and
  # #overlapping_window_scope (the sibling-window relation to check against,
  # already filtered to the same owner and active: true).
  def no_overlapping_window
    return if availability_owner_id.blank? || starts_on.blank? || ends_on.blank?

    overlapping = overlapping_window_scope
                  .where.not(id: id)
                  .where('starts_on <= ? AND ends_on >= ?', ends_on, starts_on)
                  .where('start_time < ? AND end_time > ?', end_time, start_time)

    errors.add(:base, 'overlaps with an existing availability window') if overlapping.exists?
  end
end

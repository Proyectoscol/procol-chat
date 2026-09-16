class Agents::ApplyAvailabilityScheduleJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    now = Time.current

    AgentAvailabilitySchedule.active_today.includes(:account, :user).find_each do |schedule|
      next unless schedule.applies_on?(now.to_date)

      if schedule.in_window?(now)
        lock_agent(schedule)
      else
        unlock_agent(schedule)
      end
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error("[Agents::ApplyAvailabilityScheduleJob] schedule=#{schedule.id} #{e.message}")
    end
  end

  private

  # Mirrors Api::V1::Accounts::AgentsController#account_user_params: auto_offline
  # must be forced to false alongside availability, otherwise the presence
  # heartbeat (AvailabilityStatusable) silently overrides the lock/unlock while
  # the agent's browser tab stays open (lock) or is closed (unlock) — with
  # auto_offline: true, a disconnected agent shows offline regardless of the
  # availability column (see AvailabilityStatusable#user_availability_status),
  # which is not what "back online after the break" should look like.
  #
  # find_by! (not find_by): a missing account_user is a misconfigured/impossible
  # state, and must fail loudly here rather than silently mark the schedule as
  # locked/unlocked without ever touching availability/auto_offline.
  def lock_agent(schedule)
    return if schedule.currently_locked

    account_user = schedule.account.account_users.find_by!(user_id: schedule.user_id)
    account_user.update!(availability: :offline, auto_offline: false)
    schedule.update!(currently_locked: true)
  end

  def unlock_agent(schedule)
    return unless schedule.currently_locked

    account_user = schedule.account.account_users.find_by!(user_id: schedule.user_id)
    account_user.update!(availability: :online, auto_offline: false)
    schedule.update!(currently_locked: false)
  end
end

Agents::ApplyAvailabilityScheduleJob.prepend_mod_with('Agents::ApplyAvailabilityScheduleJob')

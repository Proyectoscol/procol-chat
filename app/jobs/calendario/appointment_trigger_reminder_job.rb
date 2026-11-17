# Encolado con set(wait_until:) al crear la cita (ver Calendario::Appointment
# callbacks), uno por cada trigger before_start activo que aplique al
# servicio de la cita -- mismo patron de dispatch diferido que
# Auditoria::AdvisorDailyRollupSchedulerJob, pero por cita en vez de por
# corrida de cron.
class Calendario::AppointmentTriggerReminderJob < ApplicationJob
  queue_as :low

  def perform(trigger_id, appointment_id)
    trigger = Calendario::AppointmentEventTrigger.find_by(id: trigger_id)
    appointment = Calendario::Appointment.find_by(id: appointment_id)
    return if trigger.blank? || appointment.blank?

    Calendario::AppointmentTriggerRunner.new(trigger: trigger, appointment: appointment).perform
  end
end

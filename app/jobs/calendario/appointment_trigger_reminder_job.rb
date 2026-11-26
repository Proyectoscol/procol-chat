# Encolado con set(wait_until:) al crear la cita (ver Calendario::Appointment
# callbacks), uno por cada trigger before_start activo que aplique al
# servicio de la cita -- mismo patron de dispatch diferido que
# Auditoria::AdvisorDailyRollupSchedulerJob, pero por cita en vez de por
# corrida de cron.
class Calendario::AppointmentTriggerReminderJob < ApplicationJob
  queue_as :low

  # defer_attempt: reencolado por Calendario::AppointmentTriggerRunner
  # cuando el trigger es interactivo (tiene botones) y la conversacion ya
  # tenia otra sesion de bot activa -- ver
  # AppointmentTriggerRunner#defer_for_session_conflict?.
  def perform(trigger_id, appointment_id, defer_attempt = 0)
    trigger = Calendario::AppointmentEventTrigger.find_by(id: trigger_id)
    appointment = Calendario::Appointment.find_by(id: appointment_id)
    return if trigger.blank? || appointment.blank?

    Calendario::AppointmentTriggerRunner.new(trigger: trigger, appointment: appointment, defer_attempt: defer_attempt).perform
  end
end

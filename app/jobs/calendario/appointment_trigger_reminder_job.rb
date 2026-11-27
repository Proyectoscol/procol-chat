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
  #
  # occurrence_token: solo lo pasa Calendario::Appointment#run_on_status_change_triggers
  # para el camino demorado (delay_minutes>0) -- ese token se captura AL
  # ENCOLAR (el ultimo audit_log de cambio de estado en ese momento), no se
  # vuelve a calcular al correr el job, porque para entonces el estado pudo
  # haber cambiado otra vez (ver comentario en ese metodo). Para
  # before_start/on_reschedule/on_create, nil -- el runner lo calcula solo.
  def perform(trigger_id, appointment_id, defer_attempt = 0, occurrence_token = nil)
    trigger = Calendario::AppointmentEventTrigger.find_by(id: trigger_id)
    appointment = Calendario::Appointment.find_by(id: appointment_id)
    return if trigger.blank? || appointment.blank?

    Calendario::AppointmentTriggerRunner.new(
      trigger: trigger, appointment: appointment, defer_attempt: defer_attempt, occurrence_token: occurrence_token
    ).perform
  end
end

# Ver Calendario::AppointmentWarningsFinder para el mapeo completo de
# situaciones que generan advertencia (nunca bloqueo) al crear una cita.
class Calendario::AppointmentBookingService
  pattr_initialize [:account!, :params!, :force]

  def perform
    appointment = account.calendario_appointments.new(params)
    appointment.valid? # corre los before_validation (ej. set_ends_at_from_service) sin guardar

    warnings = Calendario::AppointmentWarningsFinder.new(
      account: account, contact_id: appointment.contact_id, professional_id: appointment.professional_id,
      starts_at: appointment.starts_at, ends_at: appointment.ends_at
    ).find
    raise Calendario::AppointmentWarningsError, warnings if warnings.any? && !force

    ensure_open_day!(appointment) if force && warnings.any? { |warning| warning[:type] == 'open_day_missing' }

    appointment.save!
    Calendario::WaitlistFulfillmentService.new(appointment: appointment).fulfill!
    appointment
  end

  private

  # El personal confirmo "crear de todas formas" sobre un dia sin agenda
  # abierta -- en vez de obligarla a ir a Agendas primero, se abre aqui mismo
  # (idempotente: ensure! no hace nada si ya quedo cubierto).
  def ensure_open_day!(appointment)
    Calendario::OpenDayCoverage.new(
      account: account, professional_id: appointment.professional_id, starts_at: appointment.starts_at
    ).ensure!
  end
end

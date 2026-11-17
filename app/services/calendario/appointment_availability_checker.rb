# Antes era una validacion dura del modelo (bloqueaba la creacion sin forma
# de continuar). Ahora es solo una consulta: un profesional sin ventanas de
# disponibilidad configuradas se considera siempre disponible, y si tiene
# ventanas pero el horario pedido cae afuera, esto NO bloquea -- solo se
# reporta como warning (ver Calendario::AppointmentWarningsFinder) porque en
# la vida real un profesional puede aceptar una excepcion a su horario.
class Calendario::AppointmentAvailabilityChecker
  pattr_initialize [:professional!, :starts_at!, :ends_at!]

  def within_availability?
    return true if professional.blank? || starts_at.blank? || ends_at.blank?

    windows = professional.availabilities.where(active: true)
    return true if windows.none?

    zone = ActiveSupport::TimeZone[professional.account&.reporting_timezone.presence || 'UTC']
    local_starts_at = starts_at.in_time_zone(zone)
    local_ends_at = ends_at.in_time_zone(zone)
    windows.any? { |window| window.covers?(local_starts_at, local_ends_at) }
  end
end

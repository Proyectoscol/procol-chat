# Responde "¿ya hay agenda abierta para este profesional en este dia/franja?"
# y, si hace falta, la abre -- mismo criterio de advertencia-no-bloqueo que
# Calendario::AppointmentAvailabilityChecker: la asistente puede confirmar un
# horario sin agenda abierta (olvido del doctor, caso excepcional) y esto
# abre la agenda por ella en vez de obligarla a ir a Agendas primero.
class Calendario::OpenDayCoverage
  pattr_initialize [:account!, :professional_id!, :starts_at!]

  def covered?
    return true if professional_id.blank? || starts_at.blank?

    Calendario::OpenDay.where(professional_id: professional_id, date: date)
                       .exists?(time_window: %w[full_day] + [window])
  end

  def ensure!
    return if covered?

    Calendario::OpenDay.create!(account: account, professional_id: professional_id, date: date, time_window: window)
  end

  def date
    local_starts_at.to_date
  end

  def window
    local_starts_at.hour < 12 ? 'morning' : 'afternoon'
  end

  private

  def local_starts_at
    zone = ActiveSupport::TimeZone[account&.reporting_timezone.presence || 'UTC']
    starts_at.in_time_zone(zone)
  end
end

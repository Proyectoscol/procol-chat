# Mapea TODAS las situaciones de "esto se ve raro pero igual puede ser
# correcto" para crear/reagendar una cita, cada una con su propio tipo para
# que el frontend las muestre como alertas distintas, nunca como una sola
# generica:
#   - contact_conflict: este contacto ya tiene otra cita activa que se
#     solapa (sin importar el profesional).
#   - professional_conflict: este profesional ya tiene otra cita activa que
#     se solapa.
#   - outside_availability: el horario pedido cae afuera de las ventanas de
#     disponibilidad configuradas del profesional.
#   - open_day_missing: todavia no se ha abierto agenda para este profesional
#     en esa fecha/franja (ver Calendario::OpenDayCoverage) -- al confirmar
#     con force, el booking service/controller abren la agenda de una vez.
# Ninguna de estas bloquea por si sola -- todas se devuelven juntas para que
# el personal confirme una sola vez y la cita se cree/actualice con force.
class Calendario::AppointmentWarningsFinder
  pattr_initialize [:account!, :contact_id!, :professional_id!, :starts_at!, :ends_at!, :exclude_id]

  def find
    [contact_conflict_warning, professional_conflict_warning, availability_warning, open_day_warning].compact
  end

  private

  def contact_conflict_warning
    conflict = Calendario::AppointmentContactConflictFinder.new(
      account: account, contact_id: contact_id, starts_at: starts_at, ends_at: ends_at, exclude_id: exclude_id
    ).find
    { type: 'contact_conflict', conflict: conflict } if conflict
  end

  def professional_conflict_warning
    conflict = Calendario::AppointmentConflictFinder.new(
      account: account, professional_id: professional_id, starts_at: starts_at, ends_at: ends_at, exclude_id: exclude_id
    ).find
    { type: 'professional_conflict', conflict: conflict } if conflict
  end

  def availability_warning
    professional = Calendario::Professional.find_by(id: professional_id)
    return nil if Calendario::AppointmentAvailabilityChecker.new(
      professional: professional, starts_at: starts_at, ends_at: ends_at
    ).within_availability?

    { type: 'outside_availability' }
  end

  def open_day_warning
    coverage = Calendario::OpenDayCoverage.new(account: account, professional_id: professional_id, starts_at: starts_at)
    return nil if coverage.covered?

    { type: 'open_day_missing', date: coverage.date, time_window: coverage.window }
  end
end

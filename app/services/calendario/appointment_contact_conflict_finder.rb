# Igual que Calendario::AppointmentConflictFinder pero del lado del contacto:
# un mismo contacto no deberia terminar con dos citas activas que se
# solapan, sin importar si son con el mismo profesional o no. No bloquea,
# solo informa (ver Calendario::AppointmentWarningsFinder).
class Calendario::AppointmentContactConflictFinder
  pattr_initialize [:account!, :contact_id!, :starts_at!, :ends_at!, :exclude_id]

  def find
    return nil if contact_id.blank? || starts_at.blank? || ends_at.blank?

    scope = account.calendario_appointments
                   .where(contact_id: contact_id)
                   .where.not(status: :cancelled)
                   .where('starts_at < ? AND ends_at > ?', ends_at, starts_at)
    scope = scope.where.not(id: exclude_id) if exclude_id
    scope.first
  end
end

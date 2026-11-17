# Compartido entre crear (Calendario::AppointmentBookingService) y reagendar
# (Api::V1::Accounts::Calendario::AppointmentsController#update) -- misma
# regla de choque en los dos casos: no bloquea, solo informa.
class Calendario::AppointmentConflictFinder
  pattr_initialize [:account!, :professional_id!, :starts_at!, :ends_at!, :exclude_id]

  def find
    return nil if professional_id.blank? || starts_at.blank? || ends_at.blank?

    scope = account.calendario_appointments
                   .where(professional_id: professional_id)
                   .where.not(status: :cancelled)
                   .where('starts_at < ? AND ends_at > ?', ends_at, starts_at)
    scope = scope.where.not(id: exclude_id) if exclude_id
    scope.first
  end
end

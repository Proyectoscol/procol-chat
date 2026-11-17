# Reemplaza a Calendario::OverlappingAppointmentError: en vez de cargar un
# solo conflicto, carga la lista completa de advertencias encontradas (ver
# Calendario::AppointmentWarningsFinder) para que el controller las devuelva
# todas juntas y el personal confirme una sola vez con force: true.
class Calendario::AppointmentWarningsError < StandardError
  attr_reader :warnings

  def initialize(warnings)
    @warnings = warnings
    super('This appointment has warnings that require confirmation')
  end
end

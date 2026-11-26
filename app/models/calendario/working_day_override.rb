# Excepcion puntual al horario laboral normal de un inbox -- pensado para
# festivos colombianos donde SI se trabaja (ej. "este 7 de agosto sí
# atendemos"), aunque tambien sirve al reves (cerrar un dia que normalmente
# seria laboral). `open: true/false` siempre gana sobre lo que diria el
# horario semanal o el calendario de festivos para esa fecha -- ver
# Calendario::BusinessHours.
class Calendario::WorkingDayOverride < ApplicationRecord
  self.table_name = 'calendario_working_day_overrides'

  belongs_to :account
  belongs_to :inbox

  validates :date, presence: true, uniqueness: { scope: :inbox_id }
end

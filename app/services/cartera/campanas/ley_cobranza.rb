# Ventana de horarios permitidos para contactar a un consumidor (Ley 2300
# de 2023, "dejen de fregar", art. 3): lunes a viernes 7:00-19:00, sabados
# 8:00-15:00, nunca domingo ni festivo. Fuente unica para la validacion del
# modelo Cartera::Campana y para la compuerta en tiempo real de
# Cartera::Campanas::CorridaService - evita que las dos definan la ventana
# por separado y se desincronicen.
module Cartera::Campanas::LeyCobranza
  # wday (Date#wday) => [hora_inicio, hora_fin], ambas inclusivas en horas enteras.
  LEGAL_WINDOWS = {
    1 => [7, 19], 2 => [7, 19], 3 => [7, 19], 4 => [7, 19], 5 => [7, 19], # lunes a viernes
    6 => [8, 15] # sabado
  }.freeze

  module_function

  def dia_permitido?(wday)
    LEGAL_WINDOWS.key?(wday)
  end

  # Rango en segundos-desde-medianoche, comparable con Time#seconds_since_midnight.
  def ventana_segundos(wday)
    inicio, fin = LEGAL_WINDOWS[wday]
    return nil if inicio.nil?

    (inicio * 3600)..(fin * 3600)
  end

  def festivo_o_domingo?(fecha)
    fecha.wday.zero? || Cartera::BusinessDays.festivo?(fecha.to_date)
  end

  def dentro_de_ventana_legal?(fecha_hora)
    return false if festivo_o_domingo?(fecha_hora)

    ventana = ventana_segundos(fecha_hora.wday)
    ventana.present? && ventana.cover?(fecha_hora.seconds_since_midnight)
  end
end

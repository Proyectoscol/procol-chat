# Calculos puros de tramo de aging, compartidos entre Cartera::AgingService
# (resumen agregado) y el listado de facturas (tramo por fila).
module Cartera::AgingCalculator
  TRAMOS = %i[vigente d1_30 d31_60 d61_90 d91_180 d181_360 mas_360].freeze

  module_function

  # Dias entre el vencimiento y la fecha de corte. Negativo o cero = vigente.
  def dias_vencido(fecha_vencimiento, fecha_corte)
    (fecha_corte.to_date - fecha_vencimiento.to_date).to_i
  end

  def tramo(dias_vencido)
    return :vigente if dias_vencido <= 0
    return :d1_30 if dias_vencido <= 30
    return :d31_60 if dias_vencido <= 60
    return :d61_90 if dias_vencido <= 90
    return :d91_180 if dias_vencido <= 180
    return :d181_360 if dias_vencido <= 360

    :mas_360
  end
end

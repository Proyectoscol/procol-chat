# Practica comercial estandar en cartera B2B colombiana (ej. "2% 10 dias").
# Simplificacion deliberada respecto al original: ventana/descuento son
# constantes (via ENV), no una tabla de configuracion editable en runtime -
# no se pidio UI de administracion para esto.
#
# Pura y deterministica: una factura abierta califica para pronto pago
# mientras la fecha de referencia no pase la ventana contada desde la
# emision. El descuento se aplica sobre el saldo pendiente ACTUAL, no sobre
# el valor original.
module Cartera::ProntoPagoCalculator
  VENTANA_DIAS = ENV.fetch('CARTERA_PRONTO_PAGO_VENTANA_DIAS', '10').to_i
  DESCUENTO_PORCENTAJE = ENV.fetch('CARTERA_PRONTO_PAGO_DESCUENTO_PORCENTAJE', '2').to_f

  module_function

  def calcular(factura, fecha_referencia = Time.current)
    saldo_pendiente = factura.saldo_pendiente.to_f
    return nil if saldo_pendiente <= 0

    fecha_limite = factura.fecha_emision.to_date + VENTANA_DIAS
    return nil if fecha_referencia.to_date > fecha_limite

    valor_pronto_pago = saldo_pendiente * (1 - (DESCUENTO_PORCENTAJE / 100))
    { fecha_limite: fecha_limite, valor_pronto_pago: valor_pronto_pago.round(2) }
  end
end

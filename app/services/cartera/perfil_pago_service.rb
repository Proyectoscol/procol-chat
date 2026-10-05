# Calcula el perfil de pago de un cliente a partir de sus facturas y pagos:
# los factores explicativos en bruto (dias promedio de pago, % pagadas
# tarde, cupo utilizado, antiguedad de la relacion...) que se muestran en la
# ficha del cliente y que alimentan Cartera::PuntajeRiesgoService. Puerto de
# perfil-pago.util.ts + .service.ts. No calcula el puntaje de riesgo final -
# ese vive en PuntajeRiesgoService, que necesita contexto de toda la cuenta
# (el saldo/facturado maximo para normalizar) que este servicio, centrado en
# un solo cliente, no tiene.
class Cartera::PerfilPagoService
  def initialize(account)
    @account = account
  end

  def calcular_perfil_deudor(cliente, fecha_referencia: Time.current)
    facturas = cliente.facturas.includes(aplicaciones_pago: :pago, notas_credito: [])
    facturas_para_perfil = facturas.map { |f| factura_para_perfil(f) }
    fechas_pagos = cliente.pagos.pluck(:fecha)
    cupo_asignado = cliente.cupo_asignado&.to_f

    perfil = calcular_perfil_pago(facturas_para_perfil, fechas_pagos, cupo_asignado, fecha_referencia)
    return perfil if cupo_asignado&.positive?

    perfil.merge(exposicion_z_score: calcular_exposicion_z_score(facturas))
  end

  # Z-score de valor_actual contra una serie historica - "que tan atipico es
  # esto para ESTE cliente", nunca un umbral global igual para todos. Null
  # con menos de 3 puntos o si la desviacion es 0.
  def calcular_z_score(serie_historica, valor_actual)
    return nil if serie_historica.length < 3

    media = serie_historica.sum / serie_historica.length.to_f
    varianza = serie_historica.sum { |v| (v - media)**2 } / serie_historica.length.to_f
    desviacion = Math.sqrt(varianza)
    return nil if desviacion.zero?

    (valor_actual - media) / desviacion
  end

  # Lleva el z-score (-inf a +inf) a 0-100: 50 es neutral, cada desviacion
  # estandar de mas suma 15 puntos, cada una de menos resta 15.
  def normalizar_z_score(z_score)
    return 50 if z_score.nil?

    (50 + (z_score * 15)).clamp(0.0, 100.0)
  end

  private

  def factura_para_perfil(factura)
    {
      fecha_vencimiento: factura.fecha_vencimiento,
      fecha_emision: factura.fecha_emision,
      valor_total: factura.valor_total.to_f,
      saldo_pendiente: factura.saldo_pendiente.to_f,
      fecha_liquidacion: fecha_liquidacion_de(factura)
    }
  end

  # Fecha de la ultima aplicacion de pago que dejo la factura en saldo 0, o
  # nil si sigue abierta.
  def fecha_liquidacion_de(factura)
    return nil if factura.saldo_pendiente.to_f.positive? || factura.aplicaciones_pago.empty?

    factura.aplicaciones_pago.map { |a| a.pago.fecha }.max
  end

  def dias_entre(desde, hasta)
    (hasta.to_time - desde.to_time) / 1.day
  end

  # rubocop:disable Metrics/MethodLength -- puerto fiel de calcularPerfilPago (perfil-pago.util.ts); ya esta descompuesta en los 4 helpers de arriba
  def calcular_perfil_pago(facturas, _fechas_pagos, cupo_asignado, fecha_referencia)
    facturas_pagadas = facturas.filter_map { |f| factura_pagada(f) }
    metricas_tiempo = calcular_metricas_tiempo_pago(facturas, facturas_pagadas)
    tendencias = calcular_tendencias(facturas_pagadas, fecha_referencia)
    metricas_cupo = calcular_metricas_cupo(facturas, cupo_asignado)

    antiguedad_relacion_dias = calcular_antiguedad_relacion_dias(facturas, fecha_referencia)

    {
      dias_promedio_pago: metricas_tiempo[:dias_promedio_pago],
      dias_promedio_pago_habil: redondear1(metricas_tiempo[:dias_promedio_pago_habil]),
      dias_mediana_pago: metricas_tiempo[:dias_mediana_pago],
      porcentaje_pagadas_tarde: metricas_tiempo[:porcentaje_pagadas_tarde],
      porcentaje_pagadas_tarde_habil: redondear1(metricas_tiempo[:porcentaje_pagadas_tarde_habil]),
      plazo_credito_tipico_dias: metricas_tiempo[:plazo_credito_tipico_dias],
      antiguedad_relacion_dias: antiguedad_relacion_dias,
      tendencia_6_meses: tendencias[:seis_meses],
      tendencia_12_meses: tendencias[:doce_meses],
      facturas_abiertas: metricas_cupo[:facturas_abiertas],
      saldo_abierto: metricas_cupo[:saldo_abierto],
      cupo_utilizado_porcentaje: metricas_cupo[:cupo_utilizado_porcentaje],
      exposicion_z_score: nil
    }
  end
  # rubocop:enable Metrics/MethodLength

  def calcular_metricas_tiempo_pago(facturas, facturas_pagadas)
    {
      dias_promedio_pago: redondear1(promedio_ponderado(facturas_pagadas.map { |f| { valor: f[:dias_pago], peso: f[:valor_total] } })),
      dias_promedio_pago_habil: promedio_ponderado(facturas_pagadas.map { |f| { valor: f[:dias_pago_habil], peso: f[:valor_total] } }),
      dias_mediana_pago: redondear1(mediana(facturas_pagadas.pluck(:dias_pago))),
      porcentaje_pagadas_tarde: redondear1(tasa_pago_tardio(facturas_pagadas.pluck(:dias_pago))),
      porcentaje_pagadas_tarde_habil: tasa_pago_tardio(facturas_pagadas.pluck(:dias_pago_habil)),
      plazo_credito_tipico_dias: redondear1(mediana(facturas.map { |f| dias_entre(f[:fecha_emision], f[:fecha_vencimiento]) }))
    }
  end

  def calcular_tendencias(facturas_pagadas, fecha_referencia)
    seis_meses = dentro_de_ventana(facturas_pagadas, 6, fecha_referencia)
    doce_meses = dentro_de_ventana(facturas_pagadas, 12, fecha_referencia)
    {
      seis_meses: { porcentaje_pagadas_tarde: tasa_pago_tardio(seis_meses.pluck(:dias_pago_habil)), cantidad_facturas: seis_meses.length },
      doce_meses: { porcentaje_pagadas_tarde: tasa_pago_tardio(doce_meses.pluck(:dias_pago_habil)), cantidad_facturas: doce_meses.length }
    }
  end

  def calcular_metricas_cupo(facturas, cupo_asignado)
    abiertas = facturas.select { |f| f[:saldo_pendiente].positive? }
    saldo_abierto = abiertas.sum { |f| f[:saldo_pendiente] }
    cupo_utilizado_porcentaje = cupo_asignado&.positive? ? (saldo_abierto / cupo_asignado) * 100 : nil

    { facturas_abiertas: abiertas.length, saldo_abierto: saldo_abierto.round(2), cupo_utilizado_porcentaje: redondear1(cupo_utilizado_porcentaje) }
  end

  def calcular_antiguedad_relacion_dias(facturas, fecha_referencia)
    fecha_primera_factura = facturas.pluck(:fecha_emision).min
    return nil if fecha_primera_factura.nil?

    [0, dias_entre(fecha_primera_factura, fecha_referencia).round].max
  end

  def factura_pagada(factura)
    return nil if factura[:fecha_liquidacion].nil?

    factura.merge(
      dias_pago: dias_entre(factura[:fecha_vencimiento], factura[:fecha_liquidacion]),
      dias_pago_habil: Cartera::BusinessDays.dias_habiles_entre(factura[:fecha_vencimiento], factura[:fecha_liquidacion])
    )
  end

  def calcular_exposicion_z_score(facturas)
    eventos = facturas.flat_map { |factura| eventos_exposicion_de(factura) }
    saldo_actual = facturas.sum { |factura| [0.0, factura.saldo_pendiente.to_f].max }

    calcular_z_score(calcular_serie_saldo_abierto(eventos), saldo_actual)
  end

  def eventos_exposicion_de(factura)
    eventos = [{ fecha: factura.fecha_emision, delta: factura.valor_total.to_f }]
    factura.aplicaciones_pago.each { |a| eventos << { fecha: a.pago.fecha, delta: -a.valor_aplicado.to_f } }
    factura.notas_credito.each { |n| eventos << { fecha: n.fecha, delta: -n.valor.to_f } }
    eventos
  end

  def calcular_serie_saldo_abierto(eventos)
    acumulado = 0.0
    eventos.sort_by { |e| e[:fecha] }.map { |e| acumulado += e[:delta] }
  end

  def dentro_de_ventana(facturas_pagadas, meses, fecha_referencia)
    facturas_pagadas.select { |f| dias_entre(f[:fecha_liquidacion], fecha_referencia) <= meses * 30 }
  end

  def mediana(valores)
    return nil if valores.empty?

    ordenados = valores.sort
    mitad = ordenados.length / 2
    ordenados.length.even? ? (ordenados[mitad - 1] + ordenados[mitad]) / 2.0 : ordenados[mitad]
  end

  def promedio_ponderado(pares)
    peso_total = pares.sum { |p| p[:peso] }
    return nil if peso_total.zero?

    pares.sum { |p| p[:valor] * p[:peso] } / peso_total
  end

  def tasa_pago_tardio(dias_pago)
    return nil if dias_pago.empty?

    (dias_pago.count(&:positive?) / dias_pago.length.to_f) * 100
  end

  def redondear1(valor)
    valor.nil? ? nil : (valor * 10).round / 10.0
  end
end

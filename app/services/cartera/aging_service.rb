# Aging de cartera (vencida y por vencer) + tendencia historica + cupos.
# Puerto de aging.util.ts + aging.service.ts.
class Cartera::AgingService
  TRAMOS_AGING = Cartera::AgingCalculator::TRAMOS
  TRAMOS_POR_VENCER = %i[d0_30 d31_60 d61_90 d91_180 d181_360 mas_360].freeze

  def initialize(account)
    @account = account
  end

  def calcular_resumen(fecha_corte: Time.current, sucursal: nil)
    facturas = facturas_abiertas_para_aging(sucursal)
    resumen = resumir_por_tramo(facturas, fecha_corte)
    por_vencer = resumir_por_vencer(facturas, fecha_corte)
    cupos = calcular_cupos(sucursal)

    {
      fecha_corte: fecha_corte,
      sucursal: sucursal,
      valor_vigente: resumen[:valor_vigente].round(2),
      valor_vencido: resumen[:valor_vencido].round(2),
      valor_total: resumen[:valor_total].round(2),
      tramos: TRAMOS_AGING.map { |t| tramo_item(resumen[:por_tramo][t], t) },
      por_vencer: TRAMOS_POR_VENCER.map { |t| tramo_item(por_vencer[:por_tramo][t], t) },
      plazo_promedio_cobro_dias: por_vencer[:plazo_promedio_cobro_dias],
      facturas_con_calidad_de_datos: contar_pagos_inconsistentes(sucursal),
      cupo_total: cupos[:cupo_total].round(2),
      cupo_disponible: cupos[:cupo_disponible].round(2)
    }
  end

  # Grafica de tendencia: cuanto era vigente/vencido en cada uno de los
  # ultimos `meses` cortes mensuales, reconstruido del historial de
  # pagos/notas credito de cada factura, sin tabla de snapshots nueva.
  def calcular_tendencia(fecha_referencia: Time.current, meses: 12, sucursal: nil)
    facturas = facturas_para_saldo_historico(sucursal)

    puntos = (0...meses).to_a.reverse.map do |i|
      corte = (fecha_referencia.to_date << i)
      valor_vigente, valor_vencido = valores_al_corte(facturas, corte)
      { mes: corte.strftime('%Y-%m'), valor_vigente: valor_vigente.round(2), valor_vencido: valor_vencido.round(2) }
    end

    { puntos: puntos }
  end

  def listar_sucursales
    @account.cartera_clientes.where.not(sucursal: [nil, '']).distinct.order(:sucursal).pluck(:sucursal)
  end

  private

  def tramo_item(datos, tramo)
    { tramo: tramo, cantidad_facturas: datos[:cantidad_facturas], valor_total: datos[:valor_total].round(2) }
  end

  def valores_al_corte(facturas, corte)
    valor_vigente = 0.0
    valor_vencido = 0.0

    facturas.each do |factura|
      saldo = saldo_al_corte(factura, corte)
      next if saldo.nil? || saldo <= 0

      tramo = Cartera::AgingCalculator.tramo(Cartera::AgingCalculator.dias_vencido(factura[:fecha_vencimiento], corte))
      if tramo == :vigente
        valor_vigente += saldo
      else
        valor_vencido += saldo
      end
    end

    [valor_vigente, valor_vencido]
  end

  def calcular_tramo_por_vencer(dias_vencido)
    return nil if dias_vencido.positive?

    dias_para_vencer = -dias_vencido
    return :d0_30 if dias_para_vencer <= 30
    return :d31_60 if dias_para_vencer <= 60
    return :d61_90 if dias_para_vencer <= 90
    return :d91_180 if dias_para_vencer <= 180
    return :d181_360 if dias_para_vencer <= 360

    :mas_360
  end

  def resumir_por_tramo(facturas, fecha_corte)
    por_tramo = TRAMOS_AGING.index_with { { cantidad_facturas: 0, valor_total: 0.0 } }
    valor_vigente = 0.0
    valor_vencido = 0.0

    facturas.each do |factura|
      tramo = Cartera::AgingCalculator.tramo(Cartera::AgingCalculator.dias_vencido(factura[:fecha_vencimiento], fecha_corte))
      por_tramo[tramo][:cantidad_facturas] += 1
      por_tramo[tramo][:valor_total] += factura[:saldo_pendiente]
      if tramo == :vigente
        valor_vigente += factura[:saldo_pendiente]
      else
        valor_vencido += factura[:saldo_pendiente]
      end
    end

    { valor_vigente: valor_vigente, valor_vencido: valor_vencido, valor_total: valor_vigente + valor_vencido, por_tramo: por_tramo }
  end

  def resumir_por_vencer(facturas, fecha_corte)
    por_tramo = TRAMOS_POR_VENCER.index_with { { cantidad_facturas: 0, valor_total: 0.0 } }
    suma_ponderada = 0.0
    suma_valor = 0.0

    facturas.each do |factura|
      dias = Cartera::AgingCalculator.dias_vencido(factura[:fecha_vencimiento], fecha_corte)
      tramo = calcular_tramo_por_vencer(dias)
      next if tramo.nil?

      por_tramo[tramo][:cantidad_facturas] += 1
      por_tramo[tramo][:valor_total] += factura[:saldo_pendiente]
      suma_ponderada += (-dias) * factura[:saldo_pendiente]
      suma_valor += factura[:saldo_pendiente]
    end

    { plazo_promedio_cobro_dias: suma_valor.positive? ? suma_ponderada / suma_valor : nil, por_tramo: por_tramo }
  end

  def saldo_al_corte(factura, fecha_corte)
    return nil if factura[:fecha_emision].to_date > fecha_corte

    aplicado = factura[:aplicaciones_pago].select { |a| a[:fecha].to_date <= fecha_corte }.sum { |a| a[:valor_aplicado] }
    acreditado = factura[:notas_credito].select { |n| n[:fecha].to_date <= fecha_corte }.sum { |n| n[:valor] }
    [0.0, factura[:valor_total] - aplicado - acreditado].max
  end

  def pago_inconsistente?(valor:, valor_aplicado:, es_anticipo:)
    return false if es_anticipo

    valor_aplicado < valor - 0.01
  end

  def facturas_abiertas_para_aging(sucursal)
    scope = @account.cartera_facturas.where('saldo_pendiente > 0')
    scope = scope.joins(:cliente).where(cartera_clientes: { sucursal: sucursal }) if sucursal
    scope.pluck(:fecha_vencimiento, :saldo_pendiente).map { |fv, sp| { fecha_vencimiento: fv, saldo_pendiente: sp.to_f } }
  end

  def facturas_para_saldo_historico(sucursal)
    scope = @account.cartera_facturas.includes(aplicaciones_pago: :pago, notas_credito: [])
    scope = scope.joins(:cliente).where(cartera_clientes: { sucursal: sucursal }) if sucursal

    scope.map do |factura|
      {
        valor_total: factura.valor_total.to_f,
        fecha_emision: factura.fecha_emision,
        fecha_vencimiento: factura.fecha_vencimiento,
        aplicaciones_pago: factura.aplicaciones_pago.map { |a| { valor_aplicado: a.valor_aplicado.to_f, fecha: a.pago.fecha } },
        notas_credito: factura.notas_credito.map { |n| { valor: n.valor.to_f, fecha: n.fecha } }
      }
    end
  end

  def calcular_cupos(sucursal)
    scope = @account.cartera_clientes.where.not(cupo_asignado: nil)
    scope = scope.where(sucursal: sucursal) if sucursal

    cupo_total = 0.0
    cupo_disponible = 0.0
    scope.includes(:facturas).find_each do |cliente|
      cupo = cliente.cupo_asignado.to_f
      saldo_abierto = cliente.facturas.select { |f| f.saldo_pendiente.to_f.positive? }.sum { |f| f.saldo_pendiente.to_f }
      cupo_total += cupo
      cupo_disponible += [0.0, cupo - saldo_abierto].max
    end
    { cupo_total: cupo_total, cupo_disponible: cupo_disponible }
  end

  def contar_pagos_inconsistentes(sucursal)
    scope = @account.cartera_clientes.joins(:pagos)
    scope = scope.where(sucursal: sucursal) if sucursal
    pagos = Cartera::Pago.where(cliente_id: scope.select(:id)).includes(:aplicaciones_pago)

    pagos.count do |pago|
      pago_inconsistente?(
        valor: pago.valor.to_f,
        valor_aplicado: pago.aplicaciones_pago.sum { |a| a.valor_aplicado.to_f },
        es_anticipo: pago.medio_pago == 'anticipo'
      )
    end
  end
end

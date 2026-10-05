# Puntaje de riesgo unificado (0-100): UNA sola formula para toda la cuenta -
# alimenta tanto el orden del panel "Clientes" (Cartera::PriorizacionService)
# como las bandas de riesgo de las reglas de campana (Cartera::Campanas::
# ReglaMatcher). Antes existian dos formulas distintas con pesos distintos
# (PriorizacionService#calcular_score para prioridad_score, PerfilPagoService
# #calcular_puntaje_riesgo para puntaje_riesgo, ambas retiradas) que podian
# estar en desacuerdo sobre que tan riesgoso es un cliente - este servicio
# las reemplaza a ambas.
#
# Los pesos vienen de Cartera::PesoRiesgo (configurable por cuenta desde
# Ajustes > Pesos del algoritmo), nunca de una constante Ruby.
class Cartera::PuntajeRiesgoService
  FACTORES = Cartera::PesoRiesgo::FACTORES

  pattr_initialize [:pesos!]

  # datos: dias_vencido_max, saldo_abierto, saldo_vencido,
  #   total_facturado_historico, porcentaje_pagadas_tarde_habil (de perfil,
  #   puede ser nil), cupo_utilizado_porcentaje (de perfil, puede ser nil),
  #   antiguedad_relacion_dias (de perfil, puede ser nil)
  # maximos: saldo_abierto, total_facturado_historico - el mayor de la
  #   cuenta, para normalizar los montos en escala logaritmica
  def calcular(datos, maximos)
    factores = normalizar_factores(datos, maximos)
    score = FACTORES.sum { |factor| factores.fetch(factor) * pesos.public_send(factor).to_f }
    { score: score.clamp(0.0, 100.0).round, factores: factores }
  end

  private

  def normalizar_factores(datos, maximos)
    {
      mora_actual: normalizar_dias(datos[:dias_vencido_max]),
      pagos_tardios: datos[:porcentaje_pagadas_tarde_habil]&.clamp(0.0, 100.0) || 50.0,
      saldo_abierto: normalizar_monto(datos[:saldo_abierto], maximos[:saldo_abierto]),
      cupo_utilizado: [100.0, datos[:cupo_utilizado_porcentaje] || 0.0].min,
      antiguedad_relacion: normalizar_antiguedad_relacion(datos[:antiguedad_relacion_dias]),
      cartera_vencida_pct: porcentaje_cartera_vencida(datos[:saldo_abierto], datos[:saldo_vencido]),
      total_facturado: normalizar_monto(datos[:total_facturado_historico], maximos[:total_facturado_historico])
    }
  end

  # 0-100, satura a los 360 dias de mora.
  def normalizar_dias(dias, tope: 360)
    return 0.0 if dias.nil?

    ((dias / tope.to_f) * 100).clamp(0.0, 100.0)
  end

  # Escala logaritmica: un solo cliente con un monto enorme no debe opacar
  # el resto del score frente al maximo de la cuenta. Reutilizado para
  # saldo_abierto y total_facturado - mismo tipo de dato (un monto en
  # pesos), misma necesidad de no dejar que un outlier sature la escala.
  def normalizar_monto(valor, maximo_cuenta)
    return 0.0 if valor.nil? || maximo_cuenta.nil? || maximo_cuenta <= 0 || valor <= 0

    ((Math.log(valor + 1) / Math.log(maximo_cuenta + 1)) * 100).clamp(0.0, 100.0)
  end

  # Mas antiguedad -> menos riesgo. Sin historial todavia (cliente nuevo
  # sin fecha de primera factura) -> neutral.
  def normalizar_antiguedad_relacion(dias)
    return 50.0 if dias.nil?

    [0.0, 100 - (dias / 365.0 * 100)].max
  end

  def porcentaje_cartera_vencida(saldo_abierto, saldo_vencido)
    return 0.0 if saldo_abierto.nil? || saldo_abierto <= 0

    ((saldo_vencido.to_f / saldo_abierto) * 100).clamp(0.0, 100.0)
  end
end

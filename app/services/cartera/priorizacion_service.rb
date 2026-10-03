# Recalcula el caso priorizado de cada cliente (score de urgencia de
# cobro + nivel de escalamiento + compuerta no_cobrar) y expone el listado
# paginado que alimenta el panel "Clientes". Puerto de priorizacion.util.ts
# + priorizacion.service.ts.
#
# Simplificacion deliberada: los pesos del score son una constante Ruby
# (PESOS_DEFAULT), no una tabla "Configuracion" editable en runtime - no se
# pidio UI de administracion para esto.
#
# rubocop:disable Metrics/ClassLength -- puerto fiel de un solo algoritmo cohesivo (priorizacion.service.ts)
class Cartera::PriorizacionService
  CLAVES_ORDEN_CLIENTES = %w[nombre_deudor saldo_abierto puntaje_riesgo prioridad_score].freeze

  PESOS_DEFAULT = { antiguedad: 0.35, monto: 0.35, probabilidad_no_pago: 0.2, tipo_cliente: 0.1 }.freeze
  PESO_POR_TIPO_DEUDOR = { empresa: 70, mixto: 55, persona_natural: 40 }.freeze
  TRAMOS_PERSUASIVO = %i[vigente d1_30 d31_60].freeze
  TRAMOS_PREJURIDICO = %i[d61_90 d91_180].freeze

  def initialize(account)
    @account = account
    @perfil_pago = Cartera::PerfilPagoService.new(account)
  end

  def recalcular(fecha_referencia: Time.current)
    clientes = cargar_clientes_con_datos(fecha_referencia)
    max_saldo_abierto = clientes.pluck(:saldo_abierto).max || 0.0

    casos_actualizados = clientes.count { |cliente| recalcular_caso_de(cliente, max_saldo_abierto, fecha_referencia) }

    Rails.logger.info("Cartera::PriorizacionService account=#{@account.id}: #{casos_actualizados} caso(s) actualizado(s).")
    { casos_actualizados: casos_actualizados }
  end

  def listar_paginado(page: 1, page_size: 20, incluir_no_cobrar: false, sort_by: nil, sort_dir: 'desc')
    page = [1, page.to_i].max
    page_size = (page_size || 20).to_i.clamp(1, 100)
    scope = @account.cartera_casos.includes(:cliente)
    scope = scope.where(no_cobrar: false) unless incluir_no_cobrar
    scope = aplicar_orden(scope, sort_by, sort_dir)

    total = scope.count
    casos = scope.offset((page - 1) * page_size).limit(page_size)

    { items: casos.map { |caso| caso_resumen(caso) }, total: total, page: page, page_size: page_size }
  end

  # Marca revisado/descartado, solo para medir adopcion.
  def marcar_estado(caso_id, revisado: nil, descartado: nil)
    caso = @account.cartera_casos.find(caso_id)
    cambios = {}
    cambios[:revisado] = revisado unless revisado.nil?
    cambios[:descartado] = descartado unless descartado.nil?
    caso.update!(cambios)
    caso
  end

  # Ficha de un cliente individual (para la vista de detalle) - mismos campos
  # que un registro de listar_paginado, construidos a partir del Cliente en
  # vez de iterar el join de Caso+Cliente.
  def ficha(cliente)
    caso = cliente.caso
    datos_cliente(cliente).merge(caso ? metricas_caso(caso).merge(estado_caso(caso)) : {})
  end

  def caso_resumen(caso)
    cliente = caso.cliente
    datos_cliente(cliente).merge(metricas_caso(caso)).merge(estado_caso(caso))
  end

  def datos_cliente(cliente)
    {
      cliente_id: cliente.id,
      nombre_cliente: cliente.nombre,
      identificacion: cliente.identificacion,
      email: cliente.email,
      sucursal: cliente.sucursal,
      cupo_asignado: cliente.cupo_asignado&.to_f,
      es_estrategico: cliente.es_estrategico,
      contact_id: cliente.contact_id,
      telefono_clasificado: Cartera::IndicativoTelefonico.clasificar_telefono(cliente.telefono, cliente.sucursal)
    }
  end

  private

  def aplicar_orden(scope, sort_by, sort_dir)
    dir = sort_dir == 'asc' ? :asc : :desc
    case sort_by
    when 'nombre_deudor' then scope.joins(:cliente).order(Cartera::Cliente.arel_table[:nombre] => dir)
    when 'saldo_abierto' then scope.order(saldo_abierto: dir)
    when 'puntaje_riesgo' then scope.order(puntaje_riesgo: dir)
    else scope.order(prioridad_score: dir)
    end
  end

  def metricas_caso(caso)
    {
      caso_id: caso.id,
      saldo_abierto: (caso.saldo_abierto || 0).to_f.round(2),
      prioridad_score: (caso.prioridad_score || 0).to_f,
      puntaje_riesgo: caso.puntaje_riesgo,
      score_credito: caso.score_credito,
      total_facturado_historico: (caso.total_facturado_historico || 0).to_f.round(2),
      facturas_abiertas_cantidad: caso.facturas_abiertas_cantidad || 0,
      fecha_primera_factura: caso.fecha_primera_factura,
      factores_score: caso.factores_score || {},
      tramo: caso.tramo,
      dias_vencido_max: caso.dias_vencido_max
    }
  end

  def estado_caso(caso)
    {
      nivel_escalamiento: caso.nivel_escalamiento,
      no_cobrar: caso.no_cobrar,
      razon_no_cobrar: caso.razon_no_cobrar,
      revisado: caso.revisado,
      descartado: caso.descartado
    }
  end

  def cargar_clientes_con_datos(fecha_referencia)
    @account.cartera_clientes.includes(facturas: :eventos_radian).map { |cliente| datos_para_priorizacion(cliente, fecha_referencia) }
  end

  def datos_para_priorizacion(cliente, fecha_referencia)
    facturas_abiertas = cliente.facturas.select { |f| f.saldo_pendiente.to_f.positive? }
    dias_vencido_max = facturas_abiertas.map { |f| dias_vencido(f.fecha_vencimiento, fecha_referencia) }.max

    {
      cliente: cliente,
      saldo_abierto: facturas_abiertas.sum { |f| f.saldo_pendiente.to_f },
      dias_vencido_max: dias_vencido_max,
      alguna_en_reclamo: facturas_abiertas.any? { |f| factura_en_reclamo?(f, fecha_referencia) },
      facturas_abiertas: facturas_abiertas
    }
  end

  def factura_en_reclamo?(factura, fecha_referencia)
    eventos = factura.eventos_radian.map { |e| { tipo_evento: e.tipo_evento, fecha: e.fecha } }
    Cartera::RadianValidator.clasificar_factura(eventos, fecha_referencia)[:estado] == :en_reclamo
  end

  def recalcular_caso_de(datos, max_saldo_abierto, fecha_referencia)
    cliente = datos[:cliente]
    sin_saldo_abierto = datos[:saldo_abierto] <= 0
    caso_existente = @account.cartera_casos.find_by(cliente: cliente)
    return false if sin_saldo_abierto && !caso_existente

    resultado = calcular_resultado_priorizacion(datos, sin_saldo_abierto, caso_existente, max_saldo_abierto, fecha_referencia)
    guardar_caso(cliente, datos, resultado)
    true
  end

  def calcular_resultado_priorizacion(datos, sin_saldo_abierto, caso_existente, max_saldo_abierto, fecha_referencia)
    cliente = datos[:cliente]
    resultado_no_cobrar = determinar_no_cobrar(
      sin_saldo_abierto: sin_saldo_abierto, es_estrategico: cliente.es_estrategico,
      alguna_factura_en_reclamo: datos[:alguna_en_reclamo], estado_caso_actual: caso_existente&.estado
    )
    perfil = sin_saldo_abierto ? nil : @perfil_pago.calcular_perfil_deudor(cliente, fecha_referencia: fecha_referencia)
    factores = calcular_factores(datos, cliente, perfil, max_saldo_abierto)

    {
      no_cobrar: resultado_no_cobrar,
      perfil: perfil,
      factores: factores,
      prioridad_score: resultado_no_cobrar[:no_cobrar] ? 0 : calcular_score(factores),
      nivel_escalamiento: sin_saldo_abierto ? 'persuasivo' : calcular_nivel_escalamiento(Cartera::AgingCalculator.tramo(datos[:dias_vencido_max]))
    }
  end

  def calcular_factores(datos, cliente, perfil, max_saldo_abierto)
    {
      antiguedad: normalizar_antiguedad([0, datos[:dias_vencido_max] || 0].max),
      monto: normalizar_monto(datos[:saldo_abierto], max_saldo_abierto),
      probabilidad_no_pago: normalizar_probabilidad_no_pago(perfil && perfil[:porcentaje_pagadas_tarde_habil]),
      tipo_cliente: PESO_POR_TIPO_DEUDOR.fetch(cliente.tipo_deudor.to_sym)
    }
  end

  def guardar_caso(cliente, datos, resultado)
    agregados = agregados_historicos(cliente)
    perfil = resultado[:perfil]
    dias_vencido_max = datos[:dias_vencido_max]
    caso = @account.cartera_casos.find_or_initialize_by(cliente: cliente)
    caso.assign_attributes(
      prioridad_score: resultado[:prioridad_score], factores_score: resultado[:factores], nivel_escalamiento: resultado[:nivel_escalamiento],
      no_cobrar: resultado[:no_cobrar][:no_cobrar], razon_no_cobrar: resultado[:no_cobrar][:razon],
      saldo_abierto: datos[:saldo_abierto].round(2),
      puntaje_riesgo: perfil && perfil[:puntaje_riesgo],
      score_credito: perfil && perfil[:score_credito],
      total_facturado_historico: agregados[:total_facturado_historico],
      facturas_abiertas_cantidad: datos[:facturas_abiertas].length,
      fecha_primera_factura: agregados[:fecha_primera_factura],
      dias_vencido_max: dias_vencido_max,
      tramo: dias_vencido_max.nil? ? nil : Cartera::AgingCalculator.tramo(dias_vencido_max).to_s
    )
    caso.save!
  end

  def agregados_historicos(cliente)
    agregados = cliente.facturas.pick(Arel.sql('SUM(valor_total), MIN(fecha_emision)'))
    { total_facturado_historico: (agregados&.first || 0).to_f.round(2), fecha_primera_factura: agregados&.second }
  end

  def dias_vencido(fecha_vencimiento, fecha_referencia)
    (fecha_referencia.to_date - fecha_vencimiento.to_date).to_i
  end

  # 0-100, satura a los 360 dias de mora.
  def normalizar_antiguedad(dias_vencido_max)
    ((dias_vencido_max / 360.0) * 100).clamp(0.0, 100.0)
  end

  # Escala logaritmica: una sola factura enorme no debe opacar el resto del
  # score frente al saldo mas grande de la cuenta.
  def normalizar_monto(saldo_abierto, max_saldo_abierto_cuenta)
    return 0.0 if max_saldo_abierto_cuenta <= 0 || saldo_abierto <= 0

    ((Math.log(saldo_abierto + 1) / Math.log(max_saldo_abierto_cuenta + 1)) * 100).clamp(0.0, 100.0)
  end

  # Sin historial de pagos todavia -> neutral (50).
  def normalizar_probabilidad_no_pago(porcentaje_pagadas_tarde)
    return 50 if porcentaje_pagadas_tarde.nil?

    porcentaje_pagadas_tarde.clamp(0.0, 100.0)
  end

  def calcular_score(factores, pesos = PESOS_DEFAULT)
    score = (factores[:antiguedad] * pesos[:antiguedad]) +
            (factores[:monto] * pesos[:monto]) +
            (factores[:probabilidad_no_pago] * pesos[:probabilidad_no_pago]) +
            (factores[:tipo_cliente] * pesos[:tipo_cliente])
    score.clamp(0.0, 100.0).round
  end

  # Regla determinista por el tramo de aging mas antiguo del cliente. Solo
  # clasificacion - no dispara ninguna accion.
  def calcular_nivel_escalamiento(tramo_mas_antiguo)
    return 'persuasivo' if TRAMOS_PERSUASIVO.include?(tramo_mas_antiguo)
    return 'prejuridico' if TRAMOS_PREJURIDICO.include?(tramo_mas_antiguo)

    'juridico'
  end

  # Compuerta previa al score, no un factor ponderado mas: una disputa no
  # debe "pesar poco", debe excluir el caso por completo.
  def determinar_no_cobrar(sin_saldo_abierto:, es_estrategico:, alguna_factura_en_reclamo:, estado_caso_actual:)
    return { no_cobrar: true, razon: 'Sin saldo abierto.' } if sin_saldo_abierto
    return { no_cobrar: true, razon: 'Cliente marcado como estrategico.' } if es_estrategico
    return { no_cobrar: true, razon: 'Tiene al menos una factura en reclamo (evento RADIAN 031).' } if alguna_factura_en_reclamo
    return { no_cobrar: true, razon: 'Tiene un acuerdo de pago en curso.' } if estado_caso_actual == 'acuerdo_en_curso'
    return { no_cobrar: true, razon: 'Caso marcado en disputa.' } if estado_caso_actual == 'disputa'

    { no_cobrar: false, razon: nil }
  end
end
# rubocop:enable Metrics/ClassLength

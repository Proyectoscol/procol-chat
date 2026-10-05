# Recalcula el caso priorizado de cada cliente (puntaje de riesgo unificado
# + nivel de escalamiento + compuerta no_cobrar) y expone el listado
# paginado que alimenta el panel "Clientes". Puerto de priorizacion.util.ts
# + priorizacion.service.ts.
#
# El puntaje en si (Cartera::PuntajeRiesgoService, con pesos configurables
# en Cartera::PesoRiesgo) es el UNICO algoritmo de riesgo de la cuenta - el
# panel "Clientes" ordena directamente por el, las bandas de riesgo de las
# reglas de campana lo leen del mismo lugar (Caso#puntaje_riesgo). Antes
# existia aqui una segunda formula aparte (prioridad_score,
# PESOS_DEFAULT/PESO_POR_TIPO_DEUDOR) que podia estar en desacuerdo con el
# puntaje que ve el usuario en la ficha del cliente - ver migracion
# RemovePrioridadScoreFromCarteraCasos.
#
# rubocop:disable Metrics/ClassLength -- puerto fiel de un solo algoritmo cohesivo (priorizacion.service.ts)
class Cartera::PriorizacionService
  CLAVES_ORDEN_CLIENTES = %w[nombre_deudor saldo_abierto puntaje_riesgo].freeze

  TRAMOS_PERSUASIVO = %i[vigente d1_30 d31_60].freeze
  TRAMOS_PREJURIDICO = %i[d61_90 d91_180].freeze

  def initialize(account)
    @account = account
    @perfil_pago = Cartera::PerfilPagoService.new(account)
    @pesos = Cartera::PesoRiesgo.para(account)
  end

  def recalcular(fecha_referencia: Time.current)
    clientes = cargar_clientes_con_datos(fecha_referencia)
    maximos = {
      saldo_abierto: clientes.pluck(:saldo_abierto).max || 0.0,
      total_facturado_historico: clientes.pluck(:total_facturado_historico).max || 0.0
    }

    casos_actualizados = clientes.count { |cliente| recalcular_caso_de(cliente, maximos, fecha_referencia) }

    Rails.logger.info("Cartera::PriorizacionService account=#{@account.id}: #{casos_actualizados} caso(s) actualizado(s).")
    { casos_actualizados: casos_actualizados }
  end

  def listar_paginado(page: 1, page_size: 20, incluir_no_cobrar: false, sort_by: nil, sort_dir: 'desc')
    page = [1, page.to_i].max
    page_size = (page_size || 20).to_i.clamp(1, 100)
    scope = casos_scope(incluir_no_cobrar: incluir_no_cobrar, sort_by: sort_by, sort_dir: sort_dir)

    total = scope.count
    casos = scope.offset((page - 1) * page_size).limit(page_size)

    { items: casos.map { |caso| caso_resumen(caso) }, total: total, page: page, page_size: page_size }
  end

  # Sin paginar, para exportar a CSV - mismo orden/filtro que listar_paginado.
  def listar_todos(incluir_no_cobrar: true, sort_by: nil, sort_dir: 'desc')
    casos_scope(incluir_no_cobrar: incluir_no_cobrar, sort_by: sort_by, sort_dir: sort_dir)
      .map { |caso| caso_resumen(caso) }
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
    # total_pagado_historico solo se calcula aqui (no en datos_cliente) -
    # datos_cliente tambien alimenta listar_paginado/listar_todos, donde
    # sumar los pagos de cada cliente en el loop seria un N+1.
    datos_cliente(cliente)
      .merge(total_pagado_historico: cliente.pagos.sum(:valor).to_f)
      .merge(caso ? metricas_caso(caso).merge(estado_caso(caso)) : {})
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
      tipo_deudor: cliente.tipo_deudor,
      email: cliente.email,
      sucursal: cliente.sucursal,
      cupo_asignado: cliente.cupo_asignado&.to_f,
      es_estrategico: cliente.es_estrategico,
      contact_id: cliente.contact_id,
      telefono_clasificado: Cartera::IndicativoTelefonico.clasificar_telefono(cliente.telefono, cliente.sucursal)
    }
  end

  private

  def casos_scope(incluir_no_cobrar:, sort_by:, sort_dir:)
    scope = @account.cartera_casos.includes(:cliente)
    scope = scope.where(no_cobrar: false) unless incluir_no_cobrar
    aplicar_orden(scope, sort_by, sort_dir)
  end

  def aplicar_orden(scope, sort_by, sort_dir)
    dir = sort_dir == 'asc' ? :asc : :desc
    case sort_by
    when 'nombre_deudor' then scope.joins(:cliente).order(Cartera::Cliente.arel_table[:nombre] => dir)
    when 'saldo_abierto' then scope.order(saldo_abierto: dir)
    else scope.order(puntaje_riesgo: dir)
    end
  end

  def metricas_caso(caso)
    {
      caso_id: caso.id,
      saldo_abierto: (caso.saldo_abierto || 0).to_f.round(2),
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
    agregados = agregados_historicos(cliente)

    {
      cliente: cliente,
      saldo_abierto: facturas_abiertas.sum { |f| f.saldo_pendiente.to_f },
      saldo_vencido: saldo_vencido_de(facturas_abiertas, fecha_referencia),
      dias_vencido_max: dias_vencido_max,
      alguna_en_reclamo: facturas_abiertas.any? { |f| factura_en_reclamo?(f, fecha_referencia) },
      facturas_abiertas: facturas_abiertas,
      total_facturado_historico: agregados[:total_facturado_historico],
      fecha_primera_factura: agregados[:fecha_primera_factura]
    }
  end

  # Parte del saldo abierto que ya esta vencida (vs. cartera corriente,
  # aun no vencida) - alimenta el factor cartera_vencida_pct del puntaje
  # de riesgo unificado.
  def saldo_vencido_de(facturas_abiertas, fecha_referencia)
    facturas_abiertas.select { |f| dias_vencido(f.fecha_vencimiento, fecha_referencia).positive? }.sum { |f| f.saldo_pendiente.to_f }
  end

  def factura_en_reclamo?(factura, fecha_referencia)
    eventos = factura.eventos_radian.map { |e| { tipo_evento: e.tipo_evento, fecha: e.fecha } }
    Cartera::RadianValidator.clasificar_factura(eventos, fecha_referencia)[:estado] == :en_reclamo
  end

  def recalcular_caso_de(datos, maximos, fecha_referencia)
    cliente = datos[:cliente]
    sin_saldo_abierto = datos[:saldo_abierto] <= 0
    caso_existente = @account.cartera_casos.find_by(cliente: cliente)
    return false if sin_saldo_abierto && !caso_existente

    resultado = calcular_resultado_priorizacion(datos, sin_saldo_abierto, caso_existente, maximos, fecha_referencia)
    guardar_caso(cliente, datos, resultado)
    true
  end

  def calcular_resultado_priorizacion(datos, sin_saldo_abierto, caso_existente, maximos, fecha_referencia)
    cliente = datos[:cliente]
    resultado_no_cobrar = determinar_no_cobrar(
      sin_saldo_abierto: sin_saldo_abierto, es_estrategico: cliente.es_estrategico,
      alguna_factura_en_reclamo: datos[:alguna_en_reclamo], estado_caso_actual: caso_existente&.estado
    )
    perfil = sin_saldo_abierto ? nil : @perfil_pago.calcular_perfil_deudor(cliente, fecha_referencia: fecha_referencia)

    {
      no_cobrar: resultado_no_cobrar,
      puntaje: calcular_puntaje(datos, perfil, maximos, resultado_no_cobrar[:no_cobrar]),
      nivel_escalamiento: sin_saldo_abierto ? 'persuasivo' : calcular_nivel_escalamiento(Cartera::AgingCalculator.tramo(datos[:dias_vencido_max]))
    }
  end

  # Un caso no_cobrar (estrategico, en disputa, acuerdo en curso, sin saldo)
  # fuerza el puntaje a 0 en vez de calcularlo - una disputa no debe "pesar
  # poco" en el puntaje que alimenta las bandas de riesgo de campana, debe
  # excluir el caso del todo.
  def calcular_puntaje(datos, perfil, maximos, no_cobrar)
    return { score: 0, factores: {} } if no_cobrar

    entrada = {
      dias_vencido_max: datos[:dias_vencido_max],
      saldo_abierto: datos[:saldo_abierto],
      saldo_vencido: datos[:saldo_vencido],
      total_facturado_historico: datos[:total_facturado_historico],
      porcentaje_pagadas_tarde_habil: perfil && perfil[:porcentaje_pagadas_tarde_habil],
      cupo_utilizado_porcentaje: perfil && perfil[:cupo_utilizado_porcentaje],
      antiguedad_relacion_dias: perfil && perfil[:antiguedad_relacion_dias]
    }
    Cartera::PuntajeRiesgoService.new(pesos: @pesos).calcular(entrada, maximos)
  end

  def guardar_caso(cliente, datos, resultado)
    dias_vencido_max = datos[:dias_vencido_max]
    puntaje_riesgo = resultado[:puntaje][:score]
    caso = @account.cartera_casos.find_or_initialize_by(cliente: cliente)
    caso.assign_attributes(
      puntaje_riesgo: puntaje_riesgo, score_credito: 100 - puntaje_riesgo, factores_score: resultado[:puntaje][:factores],
      nivel_escalamiento: resultado[:nivel_escalamiento],
      no_cobrar: resultado[:no_cobrar][:no_cobrar], razon_no_cobrar: resultado[:no_cobrar][:razon],
      saldo_abierto: datos[:saldo_abierto].round(2),
      total_facturado_historico: datos[:total_facturado_historico],
      facturas_abiertas_cantidad: datos[:facturas_abiertas].length,
      fecha_primera_factura: datos[:fecha_primera_factura],
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

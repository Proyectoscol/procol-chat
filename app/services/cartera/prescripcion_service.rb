# Alertas de prescripcion legal (art. 789 C.Co: accion cambiaria directa,
# 3 anos desde el vencimiento). No modela interrupcion (notificacion formal
# al deudor, art. 94 CGP) - requiere datos de procesos judiciales que este
# sistema no tiene. Puerto de prescripcion.util.ts + .service.ts.
class Cartera::PrescripcionService
  ANOS_PRESCRIPCION_DEFAULT = 3
  TIPO_ALERTA = 'prescripcion'.freeze
  TRAMOS_ALERTA = %w[vencida 3_meses 6_meses 12_meses].freeze
  AVISO_VALIDAR_CON_ABOGADO = 'Esta alerta es una ayuda operativa, no un concepto jurídico. Validar con abogado.'.freeze
  SUPUESTOS = [
    'Fecha límite = vencimiento + 3 años (art. 789 C.Co, acción cambiaria directa).',
    'No se modela interrupción de la prescripción (notificación formal al deudor, art. 94 CGP) - ' \
    'requiere datos de procesos judiciales que este sistema no tiene.'
  ].freeze

  def initialize(account)
    @account = account
  end

  # Idempotente: upsert por (account, tipo, factura), nunca pisa `leida`, y
  # borra las alertas que ya no aplican (ej. la factura se pago).
  def recalcular(fecha_referencia: Time.current)
    facturas_abiertas = @account.cartera_facturas.where('saldo_pendiente > 0')
    ids_vigentes = facturas_abiertas.filter_map { |factura| upsert_alerta(factura, fecha_referencia) }

    alertas_eliminadas = @account.cartera_alertas.where(tipo: TIPO_ALERTA).where.not(factura_id: ids_vigentes).delete_all

    log_resultado_recalculo(ids_vigentes.size, alertas_eliminadas)
    { alertas_vigentes: ids_vigentes.size, alertas_eliminadas: alertas_eliminadas }
  end

  def calcular_resumen(fecha_referencia: Time.current)
    por_tramo = tally_alertas_por_tramo(fecha_referencia)

    {
      fecha_corte: fecha_referencia,
      supuestos: SUPUESTOS,
      aviso: AVISO_VALIDAR_CON_ABOGADO,
      tramos: TRAMOS_ALERTA.map do |t|
        { tramo: t, cantidad_facturas: por_tramo[t][:cantidad_facturas], valor_en_riesgo: por_tramo[t][:valor_total].round(2) }
      end
    }
  end

  # Mas urgente primero (fecha limite mas cercana), paginable y filtrable
  # por leida.
  def listar_alertas(page: 1, page_size: 20, solo_no_leidas: false)
    page = [1, page.to_i].max
    page_size = page_size.to_i.clamp(1, 100)
    scope = @account.cartera_alertas.where(tipo: TIPO_ALERTA).includes(:factura, :cliente)
    scope = scope.where(leida: false) if solo_no_leidas

    total = scope.count
    alertas = scope.order(fecha_limite: :asc).offset((page - 1) * page_size).limit(page_size)

    { items: alertas.map { |a| alerta_detalle(a) }, total: total, page: page, page_size: page_size }
  end

  def marcar_leida(alerta_id, leida)
    alerta = @account.cartera_alertas.find(alerta_id)
    alerta.update!(leida: leida)
    alerta
  end

  def marcar_util(alerta_id, util)
    alerta = @account.cartera_alertas.find(alerta_id)
    alerta.update!(util: util)
    alerta
  end

  private

  def log_resultado_recalculo(alertas_vigentes, alertas_eliminadas)
    Rails.logger.info(
      "Cartera::PrescripcionService account=#{@account.id}: #{alertas_vigentes} alerta(s) vigente(s), #{alertas_eliminadas} eliminada(s)."
    )
  end

  def tally_alertas_por_tramo(fecha_referencia)
    por_tramo = TRAMOS_ALERTA.index_with { { cantidad_facturas: 0, valor_total: 0.0 } }

    @account.cartera_alertas.where(tipo: TIPO_ALERTA).find_each do |alerta|
      next if alerta.fecha_limite.nil?

      tramo = calcular_tramo_alerta(alerta.fecha_limite, fecha_referencia)
      next if tramo.nil?

      por_tramo[tramo][:cantidad_facturas] += 1
      por_tramo[tramo][:valor_total] += alerta.valor_en_riesgo.to_f
    end

    por_tramo
  end

  def upsert_alerta(factura, fecha_referencia)
    fecha_limite = calcular_fecha_limite(factura.fecha_vencimiento)
    tramo = calcular_tramo_alerta(fecha_limite, fecha_referencia)
    return nil if tramo.nil?

    mensaje = "La factura #{factura.numero} prescribe (estimado) el #{fecha_limite.iso8601} " \
              "(vencimiento + #{ANOS_PRESCRIPCION_DEFAULT} anos, art. 789 C.Co). #{AVISO_VALIDAR_CON_ABOGADO}"

    alerta = @account.cartera_alertas.find_or_initialize_by(tipo: TIPO_ALERTA, factura: factura)
    alerta.cliente_id = factura.cliente_id
    # `leida` deliberadamente NO se toca aqui.
    alerta.assign_attributes(valor_en_riesgo: factura.saldo_pendiente, fecha_limite: fecha_limite, mensaje: mensaje)
    alerta.save!
    factura.id
  end

  def alerta_detalle(alerta)
    {
      id: alerta.id,
      factura_id: alerta.factura_id,
      numero: alerta.factura&.numero || '-',
      cliente_id: alerta.cliente_id,
      nombre_cliente: alerta.cliente&.nombre || '-',
      tramo: alerta.fecha_limite ? calcular_tramo_alerta(alerta.fecha_limite, Time.current) : nil,
      fecha_limite: alerta.fecha_limite,
      valor_en_riesgo: alerta.valor_en_riesgo.to_f.round(2),
      mensaje: alerta.mensaje,
      leida: alerta.leida,
      util: alerta.util
    }
  end

  def calcular_fecha_limite(fecha_vencimiento, anos_prescripcion = ANOS_PRESCRIPCION_DEFAULT)
    fecha_vencimiento.to_date >> (anos_prescripcion * 12)
  end

  # nil = fuera de cualquier ventana de alerta todavia (a mas de 12 meses).
  def calcular_tramo_alerta(fecha_limite, fecha_referencia)
    dias_restantes = fecha_limite.to_date - fecha_referencia.to_date
    return 'vencida' if dias_restantes.negative?
    return '3_meses' if dias_restantes <= 90
    return '6_meses' if dias_restantes <= 180
    return '12_meses' if dias_restantes <= 365

    nil
  end
end

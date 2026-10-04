require 'csv'

class Api::V1::Accounts::Cartera::FacturasController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  SORTABLE = %w[numero fecha_vencimiento valor_total saldo_pendiente dias_vencidos].freeze
  CSV_HEADERS = [
    'Numero', 'Cliente', 'NIT', 'Fecha emision', 'Fecha vencimiento', 'Valor total', 'Saldo pendiente',
    'Estado', 'Tramo de mora', 'Dias vencidos', 'Fecha de pago', 'Dias de mora al pago', 'CUFE'
  ].freeze

  def index
    items = facturas_con_tramo
    items = items.select { |f| f[:tramo] == params[:tramo].to_sym } if params[:tramo].present?
    total = items.size
    items = ordenar(items)
    items = paginar(items)

    render json: { items: items, total: total, page: page, page_size: page_size }
  end

  def export
    items = facturas_con_tramo
    items = items.select { |f| f[:tramo] == params[:tramo].to_sym } if params[:tramo].present?
    items = ordenar(items)

    send_data generar_csv(items), filename: "facturas-cartera-#{Date.current.iso8601}.csv", type: 'text/csv'
  end

  def show
    factura = Current.account.cartera_facturas.includes(:cliente, :eventos_radian).find(params[:id])
    eventos = factura.eventos_radian.map { |e| { tipo_evento: e.tipo_evento, fecha: e.fecha, fuente: e.fuente } }

    render json: {
      **factura_item(factura),
      eventos_radian: eventos,
      radian: Cartera::RadianValidator.clasificar_factura(eventos, Time.current)
    }
  end

  private

  def facturas_con_tramo
    facturas_filtradas.map { |factura| factura_item(factura) }
  end

  # Por defecto trae TODAS las facturas (abiertas y pagadas) - filtrar por
  # estado es una eleccion explicita del usuario, no el default.
  def facturas_filtradas
    scope = Current.account.cartera_facturas.includes(:cliente)
    scope = scope.where(cliente_id: params[:cliente_id]) if params[:cliente_id].present?
    case params[:estado]
    when 'abiertas' then scope.where('saldo_pendiente > 0')
    when 'pagadas' then scope.where('saldo_pendiente <= 0')
    else scope
    end
  end

  # Una factura pagada no tiene "dias vencidos" ni tramo de aging - esos
  # conceptos solo aplican a saldo pendiente en vivo. Lo que sí aplica, y se
  # calcula una sola vez (no crece con el reloj), es si se pagó a tiempo o
  # con cuantos dias de mora: mismo criterio que PerfilPagoService#dias_pago.
  def factura_item(factura)
    pagada = factura.saldo_pendiente.to_f <= 0
    base = {
      factura_id: factura.id, numero: factura.numero, cliente_id: factura.cliente_id,
      nombre_cliente: factura.cliente.nombre, identificacion_cliente: factura.cliente.identificacion,
      cufe: factura.cufe, fecha_emision: factura.fecha_emision,
      fecha_vencimiento: factura.fecha_vencimiento, valor_total: factura.valor_total.to_f.round(2),
      saldo_pendiente: factura.saldo_pendiente.to_f.round(2), pagada: pagada,
      pronto_pago: Cartera::ProntoPagoCalculator.calcular(factura)
    }

    pagada ? base.merge(datos_factura_pagada(factura)) : base.merge(datos_factura_abierta(factura))
  end

  def datos_factura_abierta(factura)
    dias = Cartera::AgingCalculator.dias_vencido(factura.fecha_vencimiento, Time.current)
    { dias_vencidos: dias, tramo: Cartera::AgingCalculator.tramo(dias), fecha_pago: nil, dias_mora_pago: nil }
  end

  def datos_factura_pagada(factura)
    fecha_pago = ultima_fecha_pago(factura)
    dias_mora_pago = fecha_pago && Cartera::AgingCalculator.dias_vencido(factura.fecha_vencimiento, fecha_pago)
    { dias_vencidos: nil, tramo: nil, fecha_pago: fecha_pago, dias_mora_pago: dias_mora_pago }
  end

  def ultima_fecha_pago(factura)
    factura.aplicaciones_pago.includes(:pago).map { |a| a.pago.fecha }.max
  end

  def generar_csv(items)
    CSV.generate do |csv|
      csv << CSV_HEADERS
      items.each do |f|
        csv << [
          f[:numero], f[:nombre_cliente], f[:identificacion_cliente], fecha_csv(f[:fecha_emision]),
          fecha_csv(f[:fecha_vencimiento]), f[:valor_total], f[:saldo_pendiente],
          f[:pagada] ? 'Pagada' : 'Abierta', f[:tramo], f[:dias_vencidos], fecha_csv(f[:fecha_pago]),
          f[:dias_mora_pago], f[:cufe]
        ]
      end
    end
  end

  def fecha_csv(fecha)
    fecha&.to_date&.iso8601
  end

  def ordenar(items)
    sort_by = SORTABLE.include?(params[:sort_by]) ? params[:sort_by].to_sym : :fecha_vencimiento
    ordenados = items.sort_by { |f| f[sort_by].nil? ? 0 : f[sort_by] }
    params[:sort_dir] == 'asc' ? ordenados : ordenados.reverse
  end

  def paginar(items)
    items.slice((page - 1) * page_size, page_size) || []
  end

  def page
    [1, params[:page].to_i].max
  end

  def page_size
    (params[:page_size] || 20).to_i.clamp(1, 100)
  end
end

class Api::V1::Accounts::Cartera::FacturasController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  SORTABLE = %w[numero fecha_vencimiento valor_total saldo_pendiente dias_vencidos].freeze

  def index
    items = facturas_con_tramo
    items = items.select { |f| f[:tramo] == params[:tramo].to_sym } if params[:tramo].present?
    total = items.size
    items = ordenar(items)
    items = paginar(items)

    render json: { items: items, total: total, page: page, page_size: page_size }
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

  def factura_item(factura)
    dias = Cartera::AgingCalculator.dias_vencido(factura.fecha_vencimiento, Time.current)
    {
      factura_id: factura.id,
      numero: factura.numero,
      cliente_id: factura.cliente_id,
      nombre_cliente: factura.cliente.nombre,
      fecha_emision: factura.fecha_emision,
      fecha_vencimiento: factura.fecha_vencimiento,
      dias_vencidos: dias,
      valor_total: factura.valor_total.to_f.round(2),
      saldo_pendiente: factura.saldo_pendiente.to_f.round(2),
      pagada: factura.saldo_pendiente.to_f <= 0,
      tramo: Cartera::AgingCalculator.tramo(dias),
      pronto_pago: Cartera::ProntoPagoCalculator.calcular(factura)
    }
  end

  def ordenar(items)
    sort_by = SORTABLE.include?(params[:sort_by]) ? params[:sort_by].to_sym : :fecha_vencimiento
    ordenados = items.sort_by { |f| f[sort_by] }
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

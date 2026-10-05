require 'csv'

class Api::V1::Accounts::Cartera::ClientesController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  CSV_HEADERS = [
    'Cliente', 'NIT', 'Tipo', 'Sucursal', 'Cupo asignado', 'Saldo abierto', 'Total facturado historico',
    'Facturas abiertas', 'Puntaje de riesgo', 'Score credito', 'Tramo de mora', 'Dias vencidos (max)',
    'Nivel de escalamiento', 'No cobrar', 'Dias promedio de pago (habiles)', 'Pagadas tarde (habiles) %',
    'Cupo utilizado %', 'Antiguedad de la relacion (dias)'
  ].freeze

  def index
    render json: priorizacion.listar_paginado(
      page: params[:page], page_size: params[:page_size],
      incluir_no_cobrar: params[:incluir_no_cobrar] == 'true',
      sort_by: params[:sort_by], sort_dir: params[:sort_dir]
    )
  end

  def export
    casos = priorizacion.listar_todos(sort_by: params[:sort_by], sort_dir: params[:sort_dir])
    send_data generar_csv(casos), filename: "clientes-cartera-#{Date.current.iso8601}.csv", type: 'text/csv'
  end

  def show
    cliente = Current.account.cartera_clientes.find(params[:id])
    render json: {
      cliente: priorizacion.ficha(cliente),
      perfil_pago: Cartera::PerfilPagoService.new(Current.account).calcular_perfil_deudor(cliente),
      pagos_recientes: pagos_recientes(cliente),
      comparacion_snapshots: Cartera::ComparacionSnapshotsService.new(cliente: cliente).call
    }
  end

  def search
    termino = params[:q].to_s
    clientes = Current.account.cartera_clientes
                      .where('nombre ILIKE :q OR identificacion ILIKE :q', q: "%#{termino}%")
                      .limit(8)
                      .select(:id, :nombre, :identificacion, :tipo_deudor)

    render json: clientes.map { |c| { cliente_id: c.id, nombre: c.nombre, identificacion: c.identificacion, tipo_deudor: c.tipo_deudor } }
  end

  private

  def pagos_recientes(cliente)
    cliente.pagos.order(fecha: :desc).limit(20).map do |pago|
      { pago_id: pago.id, fecha: pago.fecha, valor: pago.valor.to_f.round(2), medio_pago: pago.medio_pago }
    end
  end

  # "Con todo el historico": ademas del caso_resumen (riesgo, saldo, tramo),
  # cada fila trae el perfil de pago completo del cliente - requiere
  # recalcularlo por cliente (no esta cacheado), aceptable para una
  # exportacion puntual, no para el listado paginado de uso frecuente.
  def generar_csv(casos)
    perfil_service = Cartera::PerfilPagoService.new(Current.account)
    clientes_por_id = Current.account.cartera_clientes.where(id: casos.pluck(:cliente_id)).index_by(&:id)

    CSV.generate do |csv|
      csv << CSV_HEADERS
      casos.each { |caso| csv << fila_csv(caso, clientes_por_id[caso[:cliente_id]], perfil_service) }
    end
  end

  def fila_csv(caso, cliente, perfil_service)
    perfil = cliente ? perfil_service.calcular_perfil_deudor(cliente) : {}
    [
      caso[:nombre_cliente], caso[:identificacion], caso[:tipo_deudor], caso[:sucursal],
      caso[:cupo_asignado], caso[:saldo_abierto], caso[:total_facturado_historico],
      caso[:facturas_abiertas_cantidad], caso[:puntaje_riesgo], caso[:score_credito],
      caso[:tramo], caso[:dias_vencido_max], caso[:nivel_escalamiento], caso[:no_cobrar],
      perfil[:dias_promedio_pago_habil], perfil[:porcentaje_pagadas_tarde_habil],
      perfil[:cupo_utilizado_porcentaje], perfil[:antiguedad_relacion_dias]
    ]
  end

  def priorizacion
    @priorizacion ||= Cartera::PriorizacionService.new(Current.account)
  end
end

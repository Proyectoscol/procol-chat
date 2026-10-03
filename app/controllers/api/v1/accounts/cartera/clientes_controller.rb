class Api::V1::Accounts::Cartera::ClientesController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  def index
    render json: priorizacion.listar_paginado(
      page: params[:page], page_size: params[:page_size],
      incluir_no_cobrar: params[:incluir_no_cobrar] == 'true',
      sort_by: params[:sort_by], sort_dir: params[:sort_dir]
    )
  end

  def show
    cliente = Current.account.cartera_clientes.find(params[:id])
    render json: {
      cliente: priorizacion.ficha(cliente),
      perfil_pago: Cartera::PerfilPagoService.new(Current.account).calcular_perfil_deudor(cliente),
      pagos_recientes: pagos_recientes(cliente)
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

  def priorizacion
    @priorizacion ||= Cartera::PriorizacionService.new(Current.account)
  end
end

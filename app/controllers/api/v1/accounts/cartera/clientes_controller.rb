class Api::V1::Accounts::Cartera::ClientesController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  def index
    render json: priorizacion.listar_paginado(
      page: params[:page], page_size: params[:page_size],
      incluir_no_cobrar: params[:incluir_no_cobrar] == 'true',
      sort_by: params[:sort_by], sort_dir: params[:sort_dir]
    )
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

  def priorizacion
    @priorizacion ||= Cartera::PriorizacionService.new(Current.account)
  end
end

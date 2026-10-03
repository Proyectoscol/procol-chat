class Api::V1::Accounts::Cartera::DashboardsController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  def show
    aging = Cartera::AgingService.new(Current.account)

    render json: {
      resumen: aging.calcular_resumen(sucursal: params[:sucursal].presence),
      tendencia: aging.calcular_tendencia(meses: (params[:meses] || 12).to_i, sucursal: params[:sucursal].presence),
      prescripcion: Cartera::PrescripcionService.new(Current.account).calcular_resumen,
      sucursales: aging.listar_sucursales
    }
  end
end

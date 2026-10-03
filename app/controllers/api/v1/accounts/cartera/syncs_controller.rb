# Disparo manual del mismo flujo que corre Cartera::SyncJob cada 15 minutos
# (ver config/schedule.yml) - para que un administrador pueda forzar una
# actualizacion sin esperar al cron, igual al boton de sincronizacion
# manual que ya existia en procol-cartera.
class Api::V1::Accounts::Cartera::SyncsController < Api::V1::Accounts::BaseController
  include Cartera::FeatureGated

  def create
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?

    connector = Cartera::ErpConnectorFactory.build
    conector_nombre = ENV.fetch('ERP_PROVEEDOR', 'alegra')

    resultado = Cartera::SyncService.new(Current.account).run(conector_nombre, connector)
    Cartera::RadianSyncService.new(Current.account).run(connector) if conector_nombre == 'alegra'
    Cartera::PrescripcionService.new(Current.account).recalcular
    Cartera::PriorizacionService.new(Current.account).recalcular

    render json: {
      estado: resultado.estado,
      registros_procesados: resultado.registros_procesados,
      errores: resultado.errores
    }
  end
end

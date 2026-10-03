# Corre la sincronizacion de cartera (clientes/facturas/pagos + eventos
# RADIAN cuando aplica) para cada cuenta con el feature flag "cartera"
# habilitado. Disparado por sidekiq-cron, ver config/schedule.yml.
class Cartera::SyncJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next unless account.feature_enabled?('cartera')

      sync_account(account)
    end
  end

  private

  def sync_account(account)
    connector = Cartera::ErpConnectorFactory.build
    conector_nombre = ENV.fetch('ERP_PROVEEDOR', 'alegra')

    Cartera::SyncService.new(account).run(conector_nombre, connector)
    Cartera::RadianSyncService.new(account).run(connector) if conector_nombre == 'alegra'

    # Mismo orden que el seed de referencia: sync -> prescripcion -> priorizacion
    # (priorizacion usa el perfil de pago, que a su vez depende de facturas/pagos
    # ya sincronizados; prescripcion no depende de priorizacion pero se corre
    # antes por convencion, sin que el orden entre ambas importe en la practica).
    Cartera::PrescripcionService.new(account).recalcular
    Cartera::PriorizacionService.new(account).recalcular
  rescue StandardError => e
    Rails.logger.error("[Cartera::SyncJob] account=#{account.id} #{e.message}")
  end
end

Cartera::SyncJob.prepend_mod_with('Cartera::SyncJob')

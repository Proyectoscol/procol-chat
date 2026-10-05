# Corre diariamente a las 8:00 (ver config/schedule.yml) para cada cuenta
# con el feature flag "cartera" habilitado - delega en CorridaService el
# trabajo por cuenta (igual que Cartera::SyncJob delega en
# Cartera::SyncService). Un error de configuracion en una cuenta (ver
# CorridaService#verificar_plantilla_lista!) no debe tumbar la corrida de
# las demas cuentas.
class Cartera::Campanas::CorridaJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next unless account.feature_enabled?('cartera')

      corer_para(account)
    end
  end

  private

  def corer_para(account)
    resultado = Cartera::Campanas::CorridaService.new(account: account).call
    Rails.logger.info("[Cartera::Campanas::CorridaJob] account=#{account.id} #{resultado}")
  rescue StandardError => e
    Rails.logger.error("[Cartera::Campanas::CorridaJob] account=#{account.id} #{e.message}")
  end
end

Cartera::Campanas::CorridaJob.prepend_mod_with('Cartera::Campanas::CorridaJob')

# Corre cada dos semanas (ver config/schedule.yml) para cada cuenta con el
# feature flag "cartera" habilitado - delega en SnapshotService el trabajo
# por cuenta, mismo patron que Cartera::Campanas::CorridaJob. Un error en
# una cuenta no debe tumbar la corrida de las demas.
class Cartera::SnapshotJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next unless account.feature_enabled?('cartera')

      fotografiar(account)
    end
  end

  private

  def fotografiar(account)
    resultado = Cartera::SnapshotService.new(account: account).call
    Rails.logger.info("[Cartera::SnapshotJob] account=#{account.id} #{resultado}")
  rescue StandardError => e
    Rails.logger.error("[Cartera::SnapshotJob] account=#{account.id} #{e.message}")
  end
end

Cartera::SnapshotJob.prepend_mod_with('Cartera::SnapshotJob')

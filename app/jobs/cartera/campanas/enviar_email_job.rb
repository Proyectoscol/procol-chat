# Ejecuta el envio real de los cartera_envios "programado" por correo -
# equivalente de Cartera::Campanas::EnviarWhatsappJob para Channel::Email.
class Cartera::Campanas::EnviarEmailJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next unless account.feature_enabled?('cartera')

      enviar_para(account)
    end
  end

  private

  def enviar_para(account)
    account.cartera_envios.where(estado: 'programado', canal: 'email').find_each do |envio|
      Cartera::Campanas::EnvioEmailService.new(envio: envio).call
    rescue StandardError => e
      Rails.logger.error("[Cartera::Campanas::EnviarEmailJob] envio=#{envio.id} #{e.message}")
    end
  end
end

Cartera::Campanas::EnviarEmailJob.prepend_mod_with('Cartera::Campanas::EnviarEmailJob')

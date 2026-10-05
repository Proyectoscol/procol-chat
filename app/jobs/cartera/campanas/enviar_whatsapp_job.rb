# Ejecuta el envio real de los cartera_envios "programado" por WhatsApp -
# separado de CorridaJob para poder ajustar la cadencia del envio sin
# tocar la logica de las compuertas. Un envio fallido (ej. telefono no
# resoluble) no debe detener el resto de la cola de esa cuenta.
class Cartera::Campanas::EnviarWhatsappJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next unless account.feature_enabled?('cartera')

      enviar_para(account)
    end
  end

  private

  def enviar_para(account)
    account.cartera_envios.where(estado: 'programado', canal: 'whatsapp').find_each do |envio|
      Cartera::Campanas::EnvioWhatsappService.new(envio: envio).call
    rescue StandardError => e
      Rails.logger.error("[Cartera::Campanas::EnviarWhatsappJob] envio=#{envio.id} #{e.message}")
    end
  end
end

Cartera::Campanas::EnviarWhatsappJob.prepend_mod_with('Cartera::Campanas::EnviarWhatsappJob')

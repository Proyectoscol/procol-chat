# Refleja en cartera_envios el estado real del Message de Twilio, que ya
# actualiza Twilio::DeliveryStatusService via webhook (entregado/leido/
# fallido, con su codigo de error) - y bloquea el canal cuando el codigo
# lo justifica. No envia nada ni consulta Twilio directamente: solo lee lo
# que el webhook ya dejo escrito en el Message.
class Cartera::Campanas::ActualizarEstadoEnviosJob < ApplicationJob
  queue_as :scheduled_jobs

  # Unico codigo de error de Twilio verificado como "este numero no esta
  # en WhatsApp" (https://www.twilio.com/docs/api/errors/63024). Cualquier
  # otro error se registra como fallido pero no bloquea el canal - no hay
  # evidencia suficiente de que sea un problema permanente del numero
  # (podria ser transitorio: limite de tasa, error temporal de Twilio).
  CODIGO_SIN_WHATSAPP = '63024'.freeze

  def perform
    Cartera::Envio.where(estado: 'enviado').where.not(message_id: nil).find_each { |envio| sincronizar(envio) }
  end

  private

  def sincronizar(envio)
    mensaje = envio.message
    return if mensaje.nil? || mensaje.status != 'failed'

    codigo = mensaje.external_error.to_s[/\d{5}/]
    envio.update!(estado: 'fallido')
    bloquear_si_corresponde(envio, codigo, mensaje.external_error)
  rescue StandardError => e
    Rails.logger.error("[Cartera::Campanas::ActualizarEstadoEnviosJob] envio=#{envio.id} #{e.message}")
  end

  def bloquear_si_corresponde(envio, codigo, detalle)
    return unless codigo == CODIGO_SIN_WHATSAPP

    envio.account.cartera_canales_bloqueados.find_or_create_by!(cliente_id: envio.cliente_id, canal: 'whatsapp') do |bloqueo|
      bloqueo.razon = 'sin_whatsapp'
      bloqueo.codigo_error = codigo
      bloqueo.detalle = detalle
      bloqueo.bloqueado_at = Time.current
    end
  end
end

Cartera::Campanas::ActualizarEstadoEnviosJob.prepend_mod_with('Cartera::Campanas::ActualizarEstadoEnviosJob')

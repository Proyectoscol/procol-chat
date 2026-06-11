# Adapter del PBX Asterisk: mismo contrato que Voice::Provider::Twilio::Adapter,
# pero SIN el baggage de conferencia (ENG-2/FIX-5). Inicializa con el Channel::Voice
# (patrón `Adapter.new(self)`), igual que el adapter de Twilio.
#
# Conexión ARI: host desde la config del canal (`ari_host`) y credenciales desde
# ENV (ASTERISK_ARI_URL/USER/PASSWORD, §9 del plan).
class Voice::Provider::Asterisk::Adapter
  ARI_TIMEOUT = 5

  def initialize(channel)
    @channel = channel
  end

  # Asterisk no usa conferencia: el navegador ya está en la llamada vía JsSIP, así
  # que el resultado NO lleva requires_agent_join ni conference_sid (FIX-5). El
  # call_sid es el Linkedid de ARI, estable durante toda la llamada y el transfer
  # (FIX-10); call_direction reusa direction_label (inbound/outbound).
  def initiate_call(call)
    {
      provider: 'asterisk',
      call_sid: call.provider_call_id,
      status: call.status,
      call_direction: call.direction_label
    }
  end

  # Transferencia ciega asesor→asesor del mismo Team (REFER vía ARI redirect).
  # true si Asterisk aceptó; false ante cualquier fallo (canal inexistente, ARI
  # caído, sin config) — nunca explota.
  def blind_transfer(call, target_extension)
    response = ari_request(:post, "channels/#{call.provider_call_id}/redirect",
                           endpoint: "PJSIP/#{target_extension}")
    ari_ok?(response)
  rescue StandardError => e
    log_failure('blind_transfer', e)
    false
  end

  # Cuelga la llamada vía ARI. Un canal ya inexistente o ARI caído → false sin
  # explotar (el teardown del consumidor es idempotente).
  def hangup(call)
    response = ari_request(:delete, "channels/#{call.provider_call_id}")
    ari_ok?(response)
  rescue StandardError => e
    log_failure('hangup', e)
    false
  end

  private

  def ari_request(method, path, query = {})
    HTTParty.public_send(
      method,
      "#{ari_base_url}/#{path}",
      query: query,
      basic_auth: ari_auth,
      timeout: ARI_TIMEOUT
    )
  end

  def ari_ok?(response)
    response.respond_to?(:success?) && response.success?
  end

  def ari_base_url
    host = config['ari_host'].presence || ENV.fetch('ASTERISK_ARI_URL', nil)
    raise 'ARI host no configurado' if host.blank?

    "#{host.to_s.chomp('/')}/ari"
  end

  def ari_auth
    {
      username: ENV.fetch('ASTERISK_ARI_USER', ''),
      password: ENV.fetch('ASTERISK_ARI_PASSWORD', '')
    }
  end

  def config
    @channel.respond_to?(:provider_config) ? (@channel.provider_config || {}) : {}
  end

  def log_failure(action, error)
    Rails.logger.error("[Voice::Provider::Asterisk::Adapter] #{action} failed: #{error.message}")
  end
end

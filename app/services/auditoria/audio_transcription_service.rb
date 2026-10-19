# Transcribe el adjunto de audio de un mensaje con Whisper/OpenAI (misma
# API key de la cuenta que ya usa Auditor IA) y guarda el texto en
# attachment.meta['transcribed_text'] -- campo nativo de Chatwoot, ya
# serializado al frontend (ver Attachment#audio_metadata) y ya usado como
# fallback de texto por Message#content_for_llm, asi que una vez guardado
# aparece solo en la burbuja de audio Y en el contexto que usa Auditor IA
# para analizar la conversacion, sin tocar ninguna vista ni el analizador.
#
# Hereda de Captain::BaseTaskService solo para reusar su resolucion de API
# key (cuenta propia via hook de OpenAI) -- no usa make_api_call (es para
# chat, no transcripcion), llama a RubyLLM.transcribe directo.
class Auditoria::AudioTranscriptionService < Captain::BaseTaskService
  pattr_initialize [:account!, :message!]

  DEFAULT_MODEL = 'gpt-4o-mini-transcribe'.freeze

  def perform
    return { error: I18n.t('captain.disabled') } unless captain_tasks_enabled?
    return { error: I18n.t('captain.api_key_missing') } unless api_key_configured?
    return { error: 'No audio attachment' } unless audio_attachment
    return { error: I18n.t('auditoria.ai_spend_limit_reached') } unless Auditoria::AiUsageLogger.within_limit?(account)

    transcribe
  rescue StandardError => e
    capture_llm_exception(e, credential: llm_credential)
    { error: e.message }
  end

  private

  def transcribe
    download_to_tempfile do |path|
      result = Llm::Config.with_api_key(api_key, api_base: api_base) do |context|
        RubyLLM.transcribe(path, model: model, context: context)
      end

      persist_result(result)
    end
  end

  # No se usa blob.open (lee del disco local de ActiveStorage): en despliegues
  # donde el proceso web y el worker de Sidekiq corren en contenedores
  # separados sin disco compartido, el archivo que escribio el proceso web
  # no existe en el disco del worker (ActiveStorage::FileNotFoundError). Se
  # descarga en cambio por HTTP desde la propia URL firmada del blob -- la
  # misma que ya usa el navegador para reproducir el audio -- asi que
  # funciona sin importar la topologia de storage del despliegue. rails_blob_url
  # (no blob.url) porque usa las default_url_options de las rutas, ya
  # configuradas para todos los entornos -- blob.url depende de
  # ActiveStorage::Current.url_options, que solo Rails setea automaticamente
  # dentro de una request web, no en un job (mismo patron ya usado en
  # Account::ContactsExportJob/LeadStatsExportJob).
  def download_to_tempfile
    blob = audio_attachment.file.blob
    url = Rails.application.routes.url_helpers.rails_blob_url(blob)
    tempfile = Tempfile.new(['auditoria_audio', File.extname(blob.filename.to_s)], binmode: true)
    response = HTTParty.get(url, follow_redirects: true)
    raise "No se pudo descargar el adjunto de audio #{blob.id}: HTTP #{response.code}" unless response.success?

    tempfile.write(response.body)
    tempfile.flush
    yield tempfile.path
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  def persist_result(result)
    audio_attachment.update!(meta: audio_attachment.meta.merge('transcribed_text' => result.text))
    log_usage(result)
    { text: result.text }
  end

  def log_usage(result)
    usage = { 'prompt_tokens' => result.input_tokens, 'completion_tokens' => result.output_tokens,
              'total_tokens' => (result.input_tokens || 0) + (result.output_tokens || 0) }
    cost_usd = Auditoria::AiCostCalculator.calculate(
      model: model, prompt_tokens: usage['prompt_tokens'], completion_tokens: usage['completion_tokens']
    )
    Auditoria::AiUsageLogger.log!(
      account: account, conversation: message.conversation, message: message, feature: :audio_transcription,
      model: model, usage: usage, cost_usd: cost_usd, triggered_by: :manual
    )
  end

  def audio_attachment
    @audio_attachment ||= message.attachments.find_by(file_type: :audio)
  end

  def model
    account.auditoria_transcription_model.presence || DEFAULT_MODEL
  end

  def event_name
    'auditoria_audio_transcription'
  end

  def use_account_openai_hook?
    true
  end
end

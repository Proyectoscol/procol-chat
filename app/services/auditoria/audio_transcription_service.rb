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
  pattr_initialize [:account!, :message!, { triggered_by: :manual }]

  DEFAULT_MODEL = 'gpt-4o-mini-transcribe'.freeze

  def perform
    guard_error = check_preconditions
    return { error: guard_error } if guard_error

    transcribe
  rescue StandardError => e
    capture_llm_exception(e, credential: llm_credential)
    { error: e.message }
  ensure
    Redis::Alfred.delete(lock_key) if @claimed_attachment
  end

  private

  def check_preconditions
    return I18n.t('captain.disabled') unless captain_tasks_enabled?
    return I18n.t('captain.api_key_missing') unless api_key_configured?
    return 'No audio attachment' unless audio_attachment
    return I18n.t('auditoria.ai_spend_limit_reached') unless Auditoria::AiUsageLogger.within_limit?(account)
    return 'Already transcribing' unless claim_attachment!

    nil
  end

  # Esta misma transcripcion puede dispararse desde 2 caminos independientes
  # sobre el MISMO adjunto: el job automatico (toggle "Transcribe Audio
  # Messages", al llegar el mensaje) y "Analizar ahora" (ver
  # Auditoria::ConversationAnalyzerService#transcribe_pending_audio!), ambos
  # chequeando el mismo transcribed_text sin coordinarse entre si. Sin este
  # lock, los dos pueden pasar ese chequeo antes de que cualquiera persista
  # el resultado -> doble llamada pagada a Whisper por el mismo audio.
  def claim_attachment!
    @claimed_attachment = Redis::Alfred.set(lock_key, '1', nx: true, ex: 2.minutes)
  end

  def lock_key
    format(Redis::RedisKeys::AUDITORIA_AUDIO_TRANSCRIPTION_LOCK, id: audio_attachment.id)
  end

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
    tempfile = Tempfile.new(['auditoria_audio', tempfile_extension(blob)], binmode: true)
    response = HTTParty.get(url, follow_redirects: true)
    raise "No se pudo descargar el adjunto de audio #{blob.id}: HTTP #{response.code}" unless response.success?

    tempfile.write(response.body)
    tempfile.flush
    yield tempfile.path
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  # OpenAI rechaza la extension .oga (la que usa WhatsApp/Chatwoot para notas
  # de voz: RubyLLM::BadRequestError "Unsupported file format oga") aunque el
  # contenido es el mismo contenedor Ogg que .ogg, que si acepta -- RubyLLM
  # sube el archivo usando File.basename del tempfile como nombre tal cual
  # (ver Provider#build_audio_file_part), asi que la extension del tempfile
  # es la que decide que formato ve la API.
  def tempfile_extension(blob)
    extension = File.extname(blob.filename.to_s)
    extension.casecmp('.oga').zero? ? '.ogg' : extension
  end

  def persist_result(result)
    audio_attachment.update!(meta: audio_attachment.meta.merge('transcribed_text' => result.text))
    message.reload.send_update_event
    # El match de categorias de palabra clave ya corrio al crear el mensaje
    # (ver Message#match_keyword_categories_for_auditoria), antes de que
    # content_for_llm tuviera transcripcion -- sin este reintento, una
    # mencion dicha solo por voz nunca entraria a auditoria_category_mentions
    # (ver Auditoria::KeywordCategoryMatcherService#transcript_rows).
    Auditoria::KeywordCategoryMatcherJob.perform_later(message.id)
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
      model: model, usage: usage, cost_usd: cost_usd, triggered_by: triggered_by
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

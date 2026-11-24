# Toma un Import::WhatsappChatBatch con un .zip de export de WhatsApp ya
# adjunto, lo descomprime, parsea el _chat.txt (Import::WhatsappChatTxtParser)
# y crea el contacto/conversacion/mensajes/adjuntos reales en Chatwoot.
#
# Seguridad contra envios reales (3 capas independientes, ninguna depende
# de las otras): todo mensaje creado aqui (entrante o saliente) lleva
# `source_id` seteado (la huella de deduplicacion) Y `private: true`.
# Base::SendOnChannelService#invalid_message? se niega a disparar un envio
# real tanto si `source_id` esta presente como si el mensaje es privado --
# cualquiera de las dos sola ya alcanza. Ademas, `content_attributes:
# {historical_import: true}` es lo que evita que listeners de dominio
# (bot de bienvenida, etc.) reaccionen a estos mensajes como si fueran
# nuevos. Para salientes ademas se usa `status: :delivered` +
# `content_attributes: {external_echo: true}` -- el mismo patron que usa
# Whatsapp::IncomingMessageBaseService para mensajes que llegaron por el
# celular y no deben reenviarse.
#
# Idempotencia: un mensaje ya importado (mismo source_id en la conversacion)
# se salta en vez de duplicarse, asi que recargar el mismo zip actualizado
# solo agrega lo nuevo. La conversacion es una sola por (contacto, inbox).
class Import::WhatsappChatImportService
  pattr_initialize [:batch!]

  def perform
    Dir.mktmpdir do |dir|
      extract_zip(dir)
      @parsed_messages = parse_chat_txt(dir)
      validate_senders!

      contact_inbox = resolve_contact_inbox
      conversation = resolve_conversation(contact_inbox)
      stats = import_messages(conversation, dir)

      batch.update!(status: :completed, contact: contact_inbox.contact, stats: stats, error_message: nil)
    end
  rescue Import::WhatsappChatNeedsReviewError => e
    batch.update!(status: :needs_review, error_message: e.message)
  end

  private

  def extract_zip(dir)
    batch.zip_file.blob.open do |tempfile|
      Zip::File.open(tempfile.path) do |zip_file|
        zip_file.each do |entry|
          next unless entry.file?

          entry.extract(entry.name, destination_directory: dir, create_parent_directories: true)
        end
      end
    end
  rescue Zip::Error => e
    raise Import::WhatsappChatParseError, "No se pudo abrir el zip: #{e.message}"
  end

  def parse_chat_txt(dir)
    chat_txt_path = find_chat_txt(dir)
    raise Import::WhatsappChatParseError, 'El zip no contiene un _chat.txt' if chat_txt_path.blank?

    Import::WhatsappChatTxtParser.new(raw_text: File.read(chat_txt_path)).parse
  end

  def find_chat_txt(dir)
    Dir.glob(File.join(dir, '**', '_chat.txt')).first || Dir.glob(File.join(dir, '**', '*.txt')).first
  end

  def validate_senders!
    senders = @parsed_messages.filter_map { |m| m[:sender_name] }.uniq
    raise Import::WhatsappChatNeedsReviewError, "Se encontraron mas de 2 remitentes distintos: #{senders.join(', ')}" if senders.size > 2
    # Un solo remitente (y no es "nosotros") no es ambiguo -- es un chat
    # donde el paciente escribio y todavia nadie del staff le ha contestado.
    # No hay con que confundirlo, asi que se importa igual: todo entrante.
    return if senders.size <= 1
    return if senders.any? { |name| sender_is_us?(name) }

    raise Import::WhatsappChatNeedsReviewError,
          "El remitente 'nosotros' (#{batch.us_sender_name}) no aparece en este chat. " \
          "Remitentes encontrados: #{senders.join(', ')}"
  end

  def sender_is_us?(name)
    name.present? && name.strip.casecmp(batch.us_sender_name.strip).zero?
  end

  def resolve_contact_inbox
    return username_contact_inbox if username_export?

    wa_id = normalized_wa_id
    ContactInboxWithContactBuilder.new(
      inbox: batch.inbox,
      source_id: whatsapp_source_id(wa_id),
      contact_attributes: { name: customer_display_name, phone_number: "+#{wa_id}" }
    ).perform
  end

  # El export de un contacto con "nombre de usuario" de WhatsApp (sin
  # numero) trae el campo telefono del batch con el username crudo, ej.
  # "@yoli.areiza" (lo escribio quien subio el zip, ver ImportWhatsappChatPage.vue).
  def username_export?
    batch.phone_number.to_s.strip.start_with?('@')
  end

  # Mismo lugar donde Whatsapp::IdentifierSyncService#additional_attributes_with_username
  # guarda el username para contactos reales via webhook -- se replica aqui
  # para que el resto de la UI (que ya lee additional_attributes.social_profiles.whatsapp)
  # lo muestre igual, sin importar si el contacto llego por import o por un
  # mensaje real.
  def username_contact_inbox
    username = normalized_username
    ContactInboxWithContactBuilder.new(
      inbox: batch.inbox,
      source_id: username_source_id(username),
      contact_attributes: {
        name: "@#{username}",
        additional_attributes: {
          'social_profiles' => { 'whatsapp' => username },
          'social_whatsapp_user_name' => username
        }
      }
    ).perform
  end

  # "@Marce93S 2.zip" vs "@Marce93S.zip" -- el sufijo " N" es el finder de
  # macOS evitando colisionar nombres de archivo en la misma carpeta al
  # exportar el mismo chat dos veces, no es parte del username real. Sin
  # esto se crearian 2 contactos distintos para la misma persona.
  def normalized_username
    batch.phone_number.to_s.strip.delete_prefix('@').sub(/\s+\d+\z/, '')
  end

  def username_source_id(username)
    inbox = batch.inbox
    return "whatsapp:@#{username}" if inbox.channel_type == 'Channel::TwilioSms' && inbox.channel.medium == 'whatsapp'

    "@#{username}"
  end

  # Channel::Whatsapp (Meta Cloud API) quiere el source_id en digitos
  # sueltos; Channel::TwilioSms en medium whatsapp lo exige como
  # "whatsapp:+E164" (ver ContactInboxBuilder#twilio_source_id, la misma
  # regla que ya usa el resto del codebase) -- sin esto, ContactInbox
  # rechaza el registro con "invalid source id for twilio whatsapp inbox".
  def whatsapp_source_id(wa_id)
    inbox = batch.inbox
    return "whatsapp:+#{wa_id}" if inbox.channel_type == 'Channel::TwilioSms' && inbox.channel.medium == 'whatsapp'

    wa_id
  end

  # 'CO' como region por defecto SOLO aplica a numeros sin "+" (ej. un
  # celular colombiano tecleado como "321 5893052") -- pasarsela tambien a
  # un numero que YA trae codigo de pais (+506, +1, etc.) hace que la
  # libreria lo valide como si fuera colombiano e ignore el codigo real,
  # rechazando numeros internacionales legitimos (Costa Rica, EEUU).
  def normalized_wa_id
    region = batch.phone_number.to_s.strip.start_with?('+') ? nil : 'CO'
    parsed = TelephoneNumber.parse(batch.phone_number, region)
    raise Import::WhatsappChatNeedsReviewError, "Numero de telefono invalido: #{batch.phone_number}" unless parsed.valid?

    parsed.e164_number.delete_prefix('+')
  end

  def customer_display_name
    @parsed_messages.filter_map { |m| m[:sender_name] }.find { |name| !sender_is_us?(name) } || batch.phone_number
  end

  def resolve_conversation(contact_inbox)
    contact_inbox.conversations.find_by(inbox_id: batch.inbox_id) || create_conversation(contact_inbox)
  end

  def create_conversation(contact_inbox)
    Conversation.create!(
      account_id: batch.account_id,
      inbox_id: batch.inbox_id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def import_messages(conversation, dir)
    stats = { imported: 0, skipped_duplicate: 0, attachments_uploaded: 0, attachments_missing: 0, errors: 0 }
    @parsed_messages.each do |parsed|
      next if parsed[:kind] == :system || parsed[:timestamp].blank?

      begin
        import_message(parsed, conversation, dir, stats)
      rescue StandardError => e
        stats[:errors] += 1
        Rails.logger.error("[Import::WhatsappChatImportService] batch=#{batch.id} message error: #{e.message}")
      end
    end
    stats
  end

  def import_message(parsed, conversation, dir, stats)
    fingerprint = message_fingerprint(parsed)
    if conversation.messages.exists?(source_id: fingerprint)
      stats[:skipped_duplicate] += 1
      return
    end

    message = conversation.messages.build(message_params(parsed, conversation, fingerprint))
    attach_file!(message, parsed[:attachment_filename], dir, stats) if parsed[:kind] == :attachment

    message.save!
    stats[:imported] += 1
  end

  def message_params(parsed, conversation, fingerprint)
    outgoing = sender_is_us?(parsed[:sender_name])
    {
      account_id: batch.account_id,
      inbox_id: batch.inbox_id,
      content: parsed[:kind] == :attachment ? nil : parsed[:body],
      message_type: outgoing ? :outgoing : :incoming,
      status: outgoing ? :delivered : :sent,
      sender: outgoing ? nil : conversation.contact,
      source_id: fingerprint,
      created_at: parsed[:timestamp],
      # private: true es una segunda capa de seguridad ademas de source_id
      # y historical_import -- Base::SendOnChannelService#invalid_message?
      # ya se niega a disparar un envio real para cualquier mensaje privado,
      # sin importar el canal. Pedido explicito del usuario tras el
      # incidente: ni source_id ni el guard de historical_import en los
      # listeners deben ser la UNICA barrera antes de pasar a produccion
      # con el numero real.
      private: true,
      # historical_import es la marca que CUALQUIER listener de
      # message_created debe revisar antes de reaccionar -- ver incidente
      # documentado en data_imports/.../INCIDENTE_welcome_bot_import.md:
      # sin esta marca, el bot de bienvenida confundio 166 conversaciones
      # recien importadas con conversaciones nuevas de verdad y mando 674
      # mensajes reales por Twilio a pacientes reales.
      content_attributes: (outgoing ? { external_echo: true } : {}).merge(historical_import: true)
    }
  end

  # Huella de deduplicacion -- tambien es el `source_id` que evita el
  # reenvio real (ver comentario de clase). No hay id nativo de WhatsApp en
  # el export, asi que se construye a partir de lo unico estable entre dos
  # exports del mismo chat: el instante (al segundo), el remitente y el
  # contenido (texto o nombre de archivo adjunto).
  def message_fingerprint(parsed)
    basis = parsed[:kind] == :attachment ? parsed[:attachment_filename] : parsed[:body]
    Digest::SHA256.hexdigest("whatsapp_import:#{parsed[:timestamp].to_i}:#{parsed[:sender_name]}:#{basis}")
  end

  def attach_file!(message, filename, dir, stats)
    if filename.blank?
      stats[:attachments_missing] += 1
      return
    end

    path = Dir.glob(File.join(dir, '**', Regexp.escape(filename))).first
    if path.blank?
      stats[:attachments_missing] += 1
      return
    end

    message.attachments.new(
      account_id: batch.account_id,
      file_type: attachment_file_type(filename),
      file: { io: File.open(path), filename: filename, content_type: Marcel::MimeType.for(Pathname.new(path)) }
    )
    stats[:attachments_uploaded] += 1
  end

  def attachment_file_type(filename)
    extension = File.extname(filename).delete_prefix('.').downcase
    return :image if %w[jpg jpeg png gif webp].include?(extension)
    return :video if %w[mp4 mov avi 3gp].include?(extension)
    return :audio if %w[opus mp3 m4a ogg aac].include?(extension)
    return :contact if extension == 'vcf'

    :file
  end
end

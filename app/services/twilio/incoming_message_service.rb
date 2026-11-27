class Twilio::IncomingMessageService # rubocop:disable Metrics/ClassLength
  include ::FileTypeHelper
  include ::Twilio::WhatsappIdentifierHelper

  pattr_initialize [:params!]

  def perform
    return if twilio_channel.blank?

    set_contact
    set_conversation
    body = message_body
    return if interactive_message? && body.blank?

    @message = @conversation.messages.build(
      content: body,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: params[:SmsSid]
    )
    @message.content_attributes = interactive_content_attributes if interactive_message?
    merge_original_replied_message_sid
    attach_files
    attach_location if location_message?
    @message.save!
  end

  private

  # Bug real encontrado en auditoria con Codex 2026-11-27 (hallazgo #6):
  # cuando el paciente toca un boton quick-reply de una plantilla (o
  # responde directamente a un mensaje), Twilio incluye el SID del mensaje
  # original en este campo -- se guarda aca para que
  # Calendario::WelcomeBotFlowRunner pueda cruzarlo contra la sesion activa
  # y detectar una respuesta a un mensaje viejo/distinto.
  def merge_original_replied_message_sid
    return if params[:OriginalRepliedMessageSid].blank?

    @message.content_attributes = @message.content_attributes.merge(
      original_replied_message_sid: params[:OriginalRepliedMessageSid]
    )
  end

  def twilio_channel
    @twilio_channel ||= ::Channel::TwilioSms.find_by(messaging_service_sid: params[:MessagingServiceSid]) if params[:MessagingServiceSid].present?
    if params[:AccountSid].present? && params[:To].present?
      @twilio_channel ||= ::Channel::TwilioSms.find_by(account_sid: params[:AccountSid],
                                                       phone_number: params[:To])
    end
    log_channel_not_found if @twilio_channel.blank?
    @twilio_channel
  end

  def log_channel_not_found
    Rails.logger.warn(
      '[TWILIO] Incoming message channel lookup failed ' \
      "account_sid=#{params[:AccountSid]} " \
      "to=#{params[:To]} " \
      "messaging_service_sid=#{params[:MessagingServiceSid]} " \
      "sms_sid=#{params[:SmsSid]}"
    )
  end

  def inbox
    @inbox ||= twilio_channel.inbox
  end

  def account
    @account ||= inbox.account
  end

  # Twilio WhatsApp phone payloads arrive as `whatsapp:+E164`. BSUID-only
  # payloads use `whatsapp:<BSUID>` in `From`, so this intentionally returns
  # nil when `From` is not phone-shaped.
  def phone_number
    return params[:From] if twilio_channel.sms?
    return unless twilio_whatsapp_phone_source?

    params[:From].gsub('whatsapp:', '')
  end

  # Keep Twilio WhatsApp source ids in Twilio's native shape. Phone messages use
  # `whatsapp:+E164`; BSUID-only messages fall back to `whatsapp:<BSUID>`.
  def normalized_phone_number
    return phone_number unless twilio_channel.whatsapp?

    twilio_whatsapp_primary_source_id
  end

  def formatted_phone_number
    return if phone_number.blank?

    TelephoneNumber.parse(phone_number).international_number
  end

  def message_body
    return interactive_parser.body if interactive_message?

    params[:Body]&.delete("\u0000")
  end

  def interactive_message?
    params[:MessageType] == 'interactive'
  end

  # Un formulario de WhatsApp Flow llega con Body vacio -- ver
  # Twilio::InteractiveMessageParser para como se reconstruye el texto y se
  # preserva el JSON crudo.
  def interactive_parser
    @interactive_parser ||= Twilio::InteractiveMessageParser.new(params: params)
  end

  def interactive_content_attributes
    interactive_parser.content_attributes
  end

  def set_contact
    source_id = twilio_channel.whatsapp? ? normalized_phone_number : params[:From]
    @contact_inbox = twilio_contact_inbox(source_id)
    @contact = @contact_inbox.contact
    update_twilio_whatsapp_identifiers

    # Update existing contact name if ProfileName is available and current name is just phone number
    update_contact_name_if_needed
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: additional_attributes
    }
  end

  def set_conversation
    # if lock to single conversation is disabled, we will create a new conversation if previous conversation is resolved
    @conversation = if @inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations.where
                                    .not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end

  def contact_attributes
    {
      name: contact_name,
      phone_number: phone_number.presence,
      additional_attributes: additional_attributes
    }
  end

  def contact_name
    params[:ProfileName].presence || formatted_phone_number || twilio_whatsapp_display_identifier || params[:From]
  end

  def additional_attributes
    if twilio_channel.sms?
      {
        from_zip_code: params[:FromZip],
        from_country: params[:FromCountry],
        from_state: params[:FromState]
      }
    else
      {}
    end
  end

  def attach_files
    num_media = params[:NumMedia].to_i
    return if num_media.zero?

    num_media.times do |i|
      media_url = params[:"MediaUrl#{i}"]
      attach_single_file(media_url) if media_url.present?
    end
  end

  def attach_single_file(media_url)
    attachment_file = download_attachment_file(media_url)
    return if attachment_file.blank?

    @message.attachments.new(
      account_id: @message.account_id,
      file_type: file_type(attachment_file.content_type),
      file: {
        io: attachment_file,
        filename: attachment_file.original_filename,
        content_type: attachment_file.content_type
      }
    )
  end

  def download_attachment_file(media_url)
    download_with_auth(media_url)
  rescue Down::Error, Down::ClientError => e
    handle_download_attachment_error(e, media_url)
  end

  def download_with_auth(media_url)
    auth_credentials = if twilio_channel.api_key_sid.present?
                         # When using api_key_sid, the auth token should be the api_secret_key
                         [twilio_channel.api_key_sid, twilio_channel.auth_token]
                       else
                         # When using account_sid, the auth token is the account's auth token
                         [twilio_channel.account_sid, twilio_channel.auth_token]
                       end

    Down.download(media_url, http_basic_authentication: auth_credentials)
  end

  def handle_download_attachment_error(error, media_url)
    Rails.logger.info "Error downloading attachment from Twilio: #{error.message}: Retrying without auth"
    Down.download(media_url)
  rescue StandardError => e
    Rails.logger.info "Error downloading attachment from Twilio: #{e.message}: Skipping"
    nil
  end

  def location_message?
    params[:MessageType] == 'location' && params[:Latitude].present? && params[:Longitude].present?
  end

  def attach_location
    @message.attachments.new(
      account_id: @message.account_id,
      file_type: :location,
      coordinates_lat: params[:Latitude].to_f,
      coordinates_long: params[:Longitude].to_f
    )
  end

  def update_contact_name_if_needed
    return if params[:ProfileName].blank?
    return if @contact.name == params[:ProfileName]

    # Only update if current name exactly matches the phone number or formatted phone number
    return unless contact_name_matches_phone_number?

    @contact.update!(name: params[:ProfileName])
  end

  def contact_name_matches_phone_number?
    return false if phone_number.blank?

    @contact.name == phone_number || @contact.name == formatted_phone_number
  end
end

class Twilio::TemplateSyncService
  pattr_initialize [:channel!]

  def call
    fetch_templates_from_twilio
    update_channel_templates
    mark_templates_updated
  rescue Twilio::REST::TwilioError => e
    Rails.logger.error("Twilio template sync failed: #{e.message}")
    false
  end

  private

  def fetch_templates_from_twilio
    @templates = client.content.v1.contents.list(limit: 1000)
  end

  def update_channel_templates
    formatted_templates = @templates.map { |template| format_template(template) }

    channel.update!(
      content_templates: { templates: formatted_templates },
      content_templates_last_updated: Time.current
    )
  end

  def format_template(template)
    approval = fetch_whatsapp_approval(template.sid)
    {
      content_sid: template.sid,
      friendly_name: template.friendly_name,
      language: template.language,
      status: approval[:status],
      template_type: derive_template_type(template),
      media_type: derive_media_type(template),
      variables: template.variables || {},
      category: approval[:category],
      body: extract_body_content(template),
      types: template.types,
      created_at: template.date_created,
      updated_at: template.date_updated
    }
  end

  # Nunca asumir 'approved' sin preguntarle a Meta -- hallazgo real de
  # 2026-11-20: varias plantillas de esta cuenta estaban "unsubmitted" (nunca
  # sometidas) y una quedo reclasificada a MARKETING al aprobarse, pero esta
  # llamada las marcaba a todas como 'approved' igual, lo cual le mentia al
  # picker de plantillas del frontend (WelcomeBotFlowFormModal/
  # AppointmentEventTriggerFormModal) sobre cuales son seguras de usar.
  # status desconocido/error de red -> 'pending', nunca 'approved' por
  # default, para que el picker (que filtra status === 'approved') nunca
  # muestre por error algo no confirmado.
  def fetch_whatsapp_approval(content_sid)
    response = api_client.fetch_approval_status(content_sid)
    whatsapp = response.success? ? JSON.parse(response.body)['whatsapp'] : nil
    { status: whatsapp&.dig('status').presence || 'pending', category: whatsapp&.dig('category').presence || 'utility' }
  rescue StandardError => e
    Rails.logger.error("Twilio::TemplateSyncService approval lookup failed for #{content_sid}: #{e.message}")
    { status: 'pending', category: 'utility' }
  end

  def api_client
    @api_client ||= Twilio::CsatTemplateApiClient.new(channel)
  end

  def mark_templates_updated
    channel.update!(content_templates_last_updated: Time.current)
  end

  def client
    @client ||= channel.send(:client)
  end

  def derive_template_type(template)
    template_types = template.types.keys

    if template_types.include?('twilio/media')
      'media'
    elsif template_types.include?('twilio/quick-reply')
      'quick_reply'
    elsif template_types.include?('twilio/call-to-action')
      'call_to_action'
    elsif template_types.include?('twilio/catalog')
      'catalog'
    else
      'text'
    end
  end

  def derive_media_type(template)
    return nil unless derive_template_type(template) == 'media'

    media_content = template.types['twilio/media']
    return nil unless media_content

    if media_content['image']
      'image'
    elsif media_content['video']
      'video'
    elsif media_content['document']
      'document'
    end
  end

  def extract_body_content(template)
    template_types = template.types

    if template_types['twilio/text']
      template_types['twilio/text']['body']
    elsif template_types['twilio/media']
      template_types['twilio/media']['body']
    elsif template_types['twilio/quick-reply']
      template_types['twilio/quick-reply']['body']
    elsif template_types['twilio/call-to-action']
      template_types['twilio/call-to-action']['body']
    elsif template_types['twilio/catalog']
      template_types['twilio/catalog']['body']
    else
      ''
    end
  end
end

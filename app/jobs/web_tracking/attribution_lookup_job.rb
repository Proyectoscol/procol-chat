# Se dispara UNA vez por conversacion nueva de WhatsApp (ver
# WebTrackingListener#conversation_created) -- busca si el numero del
# contacto ya visito urologyncare.com (tracking-api, servicio separado) y,
# si hay match, deja la navegacion visible en los atributos personalizados
# del contacto + una etiqueta con la categoria de fuente de trafico
# (organic_search/paid/direct/referral/ai_assistant, ver
# tracking-api/src/lib/traffic-source.ts -- mismos 5 valores, no se
# traducen aqui para que coincidan exactos con los que ya usa el panel de
# tracking).
class WebTracking::AttributionLookupJob < ApplicationJob
  queue_as :low

  # Las claves de abajo deben existir de antemano como
  # CustomAttributeDefinition (attribute_model: contact_attribute) --
  # sembradas una vez por cuenta (ver espacio-trabajo/.../seed_web_tracking_attributes.rb)
  # para que el panel de Chatwoot las muestre. Sin esa definicion, el
  # valor igual se guarda en custom_attributes pero queda invisible en
  # la UI hasta que se cree.
  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank? || !conversation.inbox.twilio_whatsapp?

    contact = conversation.contact
    return if contact.blank?

    service = WebTracking::VisitorLookupService.new(phone_number: contact.phone_number)
    first_message = conversation.messages.incoming.order(:created_at).first
    # Ruta real primero: correlacion por tiempo contra un click reciente de
    # "whatsapp_cta_click" al numero DEL INBOX (ver VisitorLookupService) --
    # el telefono del contacto es solo el respaldo (formulario del sitio,
    # minoria de los casos), nunca el metodo principal. message_text solo
    # se usa para desempatar si hay 2+ clicks en la ventana (ver internal.ts).
    visitor = service.by_recent_click(whatsapp_number: conversation.inbox.channel.phone_number, message_text: first_message&.content)
    visitor ||= service.by_phone
    return if visitor.blank?

    update_contact_attributes(contact, visitor)
    apply_traffic_source_label(conversation, visitor['trafficSourceCategory'])
  end

  private

  # tracking-api es Node/Drizzle -- el JSON que devuelve usa los nombres de
  # columna en camelCase (ver tracking-api/src/db/schema.ts), no snake_case.
  # Un mismatch aqui no truena nada (todo con [] en Ruby devuelve nil para
  # una key que no existe) asi que pasaba totalmente silencioso: el job
  # corria, loggeaba "match", pero guardaba todos los campos en nil salvo
  # visited_pages (que sobrevivia el .compact por quedar en "" en vez de
  # nil) -- confirmado real 2026-11-27, conversacion #349.
  def update_contact_attributes(contact, visitor)
    attributes = {
      'web_landing_page' => visitor['landingPage'],
      'web_utm_source' => visitor['utmSource'],
      'web_utm_medium' => visitor['utmMedium'],
      'web_utm_campaign' => visitor['utmCampaign'],
      'web_visit_count' => visitor['visitCount'],
      'web_visited_pages' => Array(visitor['visitedPages']).first(15).join(', ')
    }.compact

    return if attributes.blank?

    contact.update!(custom_attributes: contact.custom_attributes.merge(attributes))
  end

  def apply_traffic_source_label(conversation, category)
    return if category.blank?

    account = conversation.account
    label = account.labels.find_or_create_by!(title: category) { |l| l.description = 'Fuente de trafico (urologyncare.com)' }
    conversation.add_labels(label.title)
  end
end

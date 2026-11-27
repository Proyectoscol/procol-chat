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
    return if contact.blank? || contact.phone_number.blank?

    visitor = WebTracking::VisitorLookupService.new(phone_number: contact.phone_number).perform
    return if visitor.blank?

    update_contact_attributes(contact, visitor)
    apply_traffic_source_label(conversation, visitor['traffic_source_category'])
  end

  private

  def update_contact_attributes(contact, visitor)
    attributes = {
      'web_landing_page' => visitor['landing_page'],
      'web_utm_source' => visitor['utm_source'],
      'web_utm_medium' => visitor['utm_medium'],
      'web_utm_campaign' => visitor['utm_campaign'],
      'web_visit_count' => visitor['visit_count'],
      'web_visited_pages' => Array(visitor['visited_pages']).first(15).join(', ')
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

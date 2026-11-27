# Vincula una conversacion de WhatsApp nueva con su navegacion previa en
# urologyncare.com (tracking-api, servicio separado) -- ver
# WebTracking::AttributionLookupJob. Solo tiene sentido para WhatsApp
# (match por telefono); otros canales (email, widget) no tienen un numero
# que cruzar contra tracking-api.
class WebTrackingListener < BaseListener
  def conversation_created(event)
    conversation, account = extract_conversation_and_account(event)
    return unless conversation.inbox.twilio_whatsapp?

    WebTracking::AttributionLookupJob.perform_later(conversation.id)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end

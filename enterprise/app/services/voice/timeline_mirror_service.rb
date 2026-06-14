# Crea un activity message de llamada en la conversación activa del contacto.
# Recibe el payload crudo de Stasis (vía InternalController#handle_call_ended /
# handle_call_no_answer) para no depender del modelo Call.
#
# Orden de preferencia para la conversación donde se espeja:
#   1. WhatsApp abierta del contacto (canal más rico)
#   2. Cualquier conversación abierta fuera del inbox de Voz
#   3. Fallback: conversación en el inbox de Voz (crea si no existe)
class Voice::TimelineMirrorService
  def self.perform(payload)
    new(payload).perform
  end

  def initialize(payload)
    @payload = payload.with_indifferent_access
  end

  def perform
    inbox = resolve_inbox
    return nil unless inbox

    contact = find_or_create_contact(inbox)
    return nil unless contact

    conversation = find_or_create_conversation(inbox, contact)
    return nil unless conversation

    conversation.messages.create!(
      account_id:   conversation.account_id,
      inbox_id:     conversation.inbox_id,
      message_type: :activity,
      content:      activity_content
    )
  end

  private

  attr_reader :payload

  def event_type    = payload[:event_type].to_s
  def from_number   = payload[:from_number].to_s
  def to_number     = payload[:to].to_s
  def duration_sec  = payload[:duration_seconds].to_i
  def direction     = payload[:call_direction].to_s

  def resolve_inbox
    did = Sip::CallRoutingService.normalize_e164(to_number)
    return nil if did.blank?

    Channel::Voice.find_by(phone_number: did)&.inbox
  end

  def find_or_create_contact(inbox)
    phone = Sip::CallRoutingService.normalize_e164(from_number)
    return nil if phone.blank?

    inbox.account.contacts.find_or_create_by!(phone_number: phone) do |c|
      c.name = phone
    end
  rescue ActiveRecord::RecordInvalid
    inbox.account.contacts.find_by(phone_number: phone)
  end

  def find_or_create_conversation(inbox, contact)
    # 1) WhatsApp abierta
    wa_conv = contact.conversations
                     .joins(:inbox)
                     .where(account_id: inbox.account_id, status: :open)
                     .where(inboxes: { channel_type: 'Channel::Whatsapp' })
                     .order(last_activity_at: :desc)
                     .first
    return wa_conv if wa_conv

    # 2) Cualquier conversación abierta fuera del inbox de Voz
    other_conv = contact.conversations
                        .where(account_id: inbox.account_id, status: :open)
                        .where.not(inbox_id: inbox.id)
                        .order(last_activity_at: :desc)
                        .first
    return other_conv if other_conv

    # 3) Usar/crear conversación en el inbox de Voz
    voice_conv = contact.conversations
                        .where(account_id: inbox.account_id, inbox_id: inbox.id)
                        .where.not(status: :resolved)
                        .last
    return voice_conv if voice_conv

    contact_inbox = inbox.contact_inboxes.find_or_create_by!(contact: contact) do |ci|
      ci.source_id = "sip-#{SecureRandom.hex(6)}"
    end
    inbox.account.conversations.create!(
      contact_inbox_id: contact_inbox.id,
      inbox_id:         inbox.id,
      contact_id:       contact.id,
      status:           :open
    )
  rescue ActiveRecord::RecordNotUnique
    contact.conversations
           .where(account_id: inbox.account_id, inbox_id: inbox.id, status: :open)
           .last
  end

  def activity_content
    dir_label = direction == 'outbound' ? 'Llamada saliente' : 'Llamada entrante'
    "[#{dir_label}] Duración: #{format_duration(duration_sec)} | Estado: #{status_label} | Número: #{from_number}"
  end

  def format_duration(secs)
    return '0:00' if secs <= 0

    format('%d:%02d', secs / 60, secs % 60)
  end

  def status_label
    case event_type
    when 'ended'    then duration_sec.positive? ? 'Contestada' : 'Sin respuesta'
    when 'no_answer' then 'Sin respuesta'
    else 'Fallida'
    end
  end
end

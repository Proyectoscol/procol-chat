# Persiste un registro Call para una llamada Asterisk cerrada (evento 'ended' o
# 'no_answer'). Se llama una sola vez por llamada desde InternalController.
# Si el registro ya existe (reintento del Stasis app), sólo actualiza status y
# duration_seconds (idempotente por provider_call_id = linkedid).
class Sip::AsteriskCallLogger
  def self.call(inbox:, payload:)
    new(inbox, payload).call
  end

  def initialize(inbox, payload)
    @inbox   = inbox
    @payload = payload.with_indifferent_access
  end

  def call
    contact      = find_or_create_contact
    return nil unless contact

    contact_inbox = find_or_create_contact_inbox(contact)
    conversation  = find_or_create_conversation(contact, contact_inbox)

    create_or_update_call(contact, conversation)
  rescue => e
    Rails.logger.error "[SIP] AsteriskCallLogger failed: #{e.class} #{e.message}"
    nil
  end

  private

  def phone
    @phone ||= Sip::CallRoutingService.normalize_e164(@payload[:from_number].to_s)
  end

  def linkedid     = @payload[:linkedid].to_s
  def duration_sec = @payload[:duration_seconds].to_i
  def event_type   = @payload[:event_type].to_s

  def final_status
    return 'no_answer' if event_type == 'no_answer'

    duration_sec.positive? ? 'completed' : 'no_answer'
  end

  def find_or_create_contact
    return nil if phone.blank?

    @inbox.account.contacts.find_or_create_by!(phone_number: phone) do |c|
      c.name = phone
    end
  rescue ActiveRecord::RecordInvalid
    @inbox.account.contacts.find_by(phone_number: phone)
  end

  def find_or_create_contact_inbox(contact)
    @inbox.contact_inboxes.find_or_create_by!(contact: contact) do |ci|
      ci.source_id = "sip-#{linkedid.presence || SecureRandom.hex(6)}"
    end
  rescue ActiveRecord::RecordNotUnique
    @inbox.contact_inboxes.find_by!(contact: contact)
  end

  def find_or_create_conversation(contact, contact_inbox)
    contact_inbox.conversations.where.not(status: :resolved).last ||
      @inbox.account.conversations.create!(
        contact_inbox_id: contact_inbox.id,
        inbox_id:         @inbox.id,
        contact_id:       contact.id,
        status:           :open
      )
  end

  def create_or_update_call(contact, conversation)
    existing = Call.find_by(provider: :asterisk, provider_call_id: linkedid)
    if existing
      existing.update!(status: final_status, duration_seconds: duration_sec)
      return existing
    end

    Call.create!(
      account:         @inbox.account,
      inbox:           @inbox,
      conversation:    conversation,
      contact:         contact,
      provider:        :asterisk,
      direction:       :incoming,
      provider_call_id: linkedid.presence || "sip-#{SecureRandom.hex(8)}",
      status:          final_status,
      duration_seconds: duration_sec
    )
  rescue ActiveRecord::RecordNotUnique
    Call.find_by(provider: :asterisk, provider_call_id: linkedid)
  end
end

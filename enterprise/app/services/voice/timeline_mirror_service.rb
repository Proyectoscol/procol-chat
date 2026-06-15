# Crea un activity message de llamada en TODAS las conversaciones activas del contacto.
# Recibe el payload crudo de Stasis (vía InternalController#handle_call_ended /
# handle_call_no_answer) para no depender del modelo Call.
#
# Si el contacto no tiene conversaciones abiertas/pendientes, crea una en el inbox de Voz.
# Idempotente: un mismo linkedid no genera duplicados en la misma conversación.
# Si la llamada fue contestada (duration > 0), asigna la conversación al asesor que atendió.
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

    agent         = sip_agent(inbox.account_id)
    conversations = target_conversations(contact, inbox)

    conversations.each do |conversation|
      next if already_recorded?(conversation, linkedid)

      conversation.messages.create!(
        account_id:            conversation.account_id,
        inbox_id:              conversation.inbox_id,
        message_type:          :activity,
        content:               activity_content(agent),
        additional_attributes: { linkedid: linkedid }.compact
      )

      assign_agent_if_answered(conversation, agent)
    end
  end

  private

  attr_reader :payload

  def event_type   = payload[:event_type].to_s
  def from_number  = payload[:from_number].to_s
  def to_number    = payload[:to].to_s
  def duration_sec = payload[:duration_seconds].to_i
  def direction    = payload[:call_direction].to_s
  def linkedid     = payload[:linkedid].to_s

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

  # Retorna TODAS las conversaciones abiertas/pendientes del contacto en esta cuenta.
  # Si no hay ninguna, crea (o reutiliza) una en el inbox de Voz como fallback.
  def target_conversations(contact, voice_inbox)
    open_convs = contact.conversations
                        .where(account_id: voice_inbox.account_id, status: [:open, :pending])
                        .to_a
    return open_convs if open_convs.any?

    [find_or_create_voice_conversation(contact, voice_inbox)]
  end

  def find_or_create_voice_conversation(contact, inbox)
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

  # Evita duplicados si el mismo evento llega dos veces (retry de Stasis / red).
  def already_recorded?(conversation, lid)
    return false if lid.blank?

    conversation.messages
                .where(message_type: :activity)
                .where("additional_attributes->>'linkedid' = ?", lid)
                .exists?
  end

  # Resuelve el User a partir de la extensión SIP del payload.
  def sip_agent(account_id)
    ext = payload[:to_extension].to_s.gsub(/\D/, '')
    return nil if ext.blank?

    SipIdentity.find_by(account_id: account_id, sip_extension: ext)&.user
  end

  # Asigna la conversación al asesor solo si la llamada fue contestada y la
  # conversación aún no tiene asignado. Usa el service oficial de Chatwoot
  # para que dispare el evento ASSIGNEE_CHANGED y actualice el ActionCable.
  def assign_agent_if_answered(conversation, agent)
    return unless duration_sec.positive?
    return unless agent
    return unless conversation.assignee_id.nil?

    Conversations::AssignmentService.new(
      conversation: conversation,
      assignee_id:  agent.id
    ).perform
  rescue StandardError => e
    Rails.logger.warn "[VoIP] assign_agent_if_answered failed conv=#{conversation.id}: #{e.message}"
  end

  def activity_content(agent)
    dir_label  = direction == 'outbound' ? 'Llamada saliente' : 'Llamada entrante'
    agent_text = agent ? " | Asesor: #{agent.name} (ext. #{payload[:to_extension]})" : ''
    "[#{dir_label}] Duración: #{format_duration(duration_sec)} | Estado: #{status_label} | Número: #{from_number}#{agent_text}"
  end

  def format_duration(secs)
    return '0:00' if secs <= 0

    format('%d:%02d', secs / 60, secs % 60)
  end

  def status_label
    case event_type
    when 'ended'     then duration_sec.positive? ? 'Contestada' : 'Sin respuesta'
    when 'no_answer' then 'Sin respuesta'
    else 'Fallida'
    end
  end
end

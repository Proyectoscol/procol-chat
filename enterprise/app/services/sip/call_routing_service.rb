# Servicio de entrada del routing de voz Asterisk (Lane B, §3 del plan).
#
# Decide la PRIMERA bifurcación de una llamada entrante en la bandeja de Voz:
#   - Si el número que llama corresponde a un contacto con asesor asignado
#     (y ese asesor tiene una extensión SIP) → suena solo a él: { extension:, agent: }
#   - En cualquier otro caso → IVR: { ivr: true }
#
# Antes de buscar el contacto, normaliza el número a E164 (FIX-8) para no forkear
# un contacto nuevo cuando Asterisk entrega el número sin '+' o con prefijos.
#
# La lógica fina de presencia/ocupado/ausencia (Casos A/B/C, RR de Team, cola,
# buzón) NO vive aquí: es del pipeline de reglas `Sip::RoutingDecisionService`
# (§14.2/§17.2). Este servicio es el lookup indexado de entrada y nada más.
class Sip::CallRoutingService
  attr_reader :inbox, :from_number

  def self.call(inbox:, from_number:)
    new(inbox: inbox, from_number: from_number).call
  end

  # Punto único de normalización E164 para el routing de voz (FIX-8): conserva
  # dígitos y un único '+' inicial; si llega sin indicativo asume Colombia (+57).
  # Reusado por las reglas de routing (p. ej. SharedNumberRule). La normalización
  # específica de WhatsApp (wa_id BR/AR) vive en Whatsapp::PhoneNumberNormalizationService.
  def self.normalize_e164(raw)
    digits = raw.to_s.gsub(/[^\d+]/, '')
    return '' if digits.blank?

    return digits if digits.start_with?('+')
    return "+#{digits}" if digits.start_with?('57')

    "+57#{digits}"
  end

  def initialize(inbox:, from_number:)
    @inbox = inbox
    @from_number = from_number
  end

  # @return [Hash] { extension: String, agent: User } | { ivr: true }
  def call
    contact = find_contact
    return ivr_result unless contact

    agent = assigned_agent(contact)
    return ivr_result unless agent

    identity = sip_identity_for(agent)
    return ivr_result unless identity

    { extension: identity.sip_extension, agent: agent }
  end

  private

  def account
    inbox.account
  end

  def ivr_result
    { ivr: true }
  end

  # Lookup indexado por (account_id, phone_number). El número se normaliza a E164
  # para coincidir con cómo Chatwoot almacena los contactos (+57...).
  def find_contact
    e164 = self.class.normalize_e164(from_number)
    return nil if e164.blank?

    account.contacts.find_by(phone_number: e164)
  end

  # Asesor "dueño" del contacto = quien tiene asignada su conversación más reciente
  # en la bandeja de Voz. Un contacto que nunca ha llamado no tiene asignado → IVR.
  def assigned_agent(contact)
    contact.conversations
           .where(inbox_id: inbox.id)
           .where.not(assignee_id: nil)
           .order(last_activity_at: :desc)
           .first
           &.assignee
  end

  # UNIQUE (account_id, user_id): a lo sumo una identidad SIP por asesor y cuenta.
  def sip_identity_for(agent)
    SipIdentity.find_by(account_id: account.id, user_id: agent.id)
  end
end

# Fuente de verdad de la presencia SIP (FIX-3, AREA1-G1/G4, multi-dispositivo §15.1).
# Procesa los eventos register/unregister/sync que la app Stasis envía por
# POST /sip/events. La presencia real es el REGISTER PJSIP (AMI), no el dashboard:
# un asesor está disponible para voz si sip_active_contacts > 0.
#
#   register   → +1 (PC/Android/tablet suman). En la transición 0→1 marca
#                sip_last_registered_at y limpia sip_absence_alerted_at (dedup alertas).
#   unregister → -1 con piso 0 (nunca negativo).
#   sync       → reconcilia al nº real de contactos PJSIP por extensión (corrige
#                deriva si se perdió un evento). Extensión ausente de la lista → 0.
#
# Multi-cliente: todo va scopeado a la cuenta (la extensión '1001' puede existir
# en varias cuentas, UNIQUE por (account_id, sip_extension)).
class Sip::PresenceService
  attr_reader :account

  def initialize(account:)
    @account = account
  end

  # @return [SipIdentity, nil] nil si la extensión no existe en la cuenta.
  def register(extension)
    update_identity(extension) do |identity|
      identity.sip_active_contacts += 1
      mark_first_device(identity) if identity.sip_active_contacts == 1
    end
  end

  # @return [SipIdentity, nil]
  def unregister(extension)
    update_identity(extension) do |identity|
      identity.sip_active_contacts = [identity.sip_active_contacts - 1, 0].max
    end
  end

  # @param registered [Array<Hash>, Hash] [{ ext:, count: }, ...] o { ext => count }.
  # @return [Integer] nº de identidades reconciliadas.
  def sync(registered)
    counts = normalize_counts(registered)
    identities = SipIdentity.where(account_id: account.id)
    identities.find_each { |identity| reconcile(identity, counts[identity.sip_extension].to_i) }
    identities.count
  end

  private

  def find_identity(extension)
    SipIdentity.find_by(account_id: account.id, sip_extension: extension.to_s)
  end

  # Bloqueo de fila (SELECT ... FOR UPDATE) para que registros simultáneos de varios
  # dispositivos del mismo asesor no pisen el contador.
  def update_identity(extension)
    identity = find_identity(extension)
    return nil unless identity

    identity.with_lock do
      yield identity
      identity.save!
    end
    identity
  end

  def reconcile(identity, target)
    identity.with_lock do
      was_zero = identity.sip_active_contacts.to_i.zero?
      identity.sip_active_contacts = target
      mark_first_device(identity) if target.positive? && was_zero
      identity.save!
    end
  end

  # Transición a "presente": primer dispositivo registrado. Marca la hora y borra
  # la alerta de ausencia para que vuelva a poder alertarse en el futuro.
  def mark_first_device(identity)
    identity.sip_last_registered_at = Time.current
    identity.sip_absence_alerted_at = nil
  end

  def normalize_counts(registered)
    case registered
    when Hash
      registered.transform_keys(&:to_s).transform_values { |v| v.to_i }
    when Array
      registered.each_with_object({}) do |item, acc|
        row = item.respond_to?(:with_indifferent_access) ? item.with_indifferent_access : {}
        ext = (row[:ext] || row[:extension]).to_s
        acc[ext] = row[:count].to_i if ext.present?
      end
    else
      {}
    end
  end
end

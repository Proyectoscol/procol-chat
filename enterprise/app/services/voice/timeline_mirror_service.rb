# Visualización opción B (§1/§3): al estado terminal de una llamada Asterisk,
# espeja un activity INMUTABLE en la conversación ABIERTA del contacto en OTRO
# inbox (WhatsApp u otro canal), enlazando la llamada al timeline unificado.
#
# message_type: :activity = mensaje de sistema: no editable ni borrable por el
# asesor (esa es la inmutabilidad que pide el plan). Reusa el patrón canónico de
# Chatwoot (conversation.messages.create! con activity params).
#
# Degrada limpio: si el contacto no tiene conversación abierta fuera de Voz, no-op
# (devuelve nil sin error). Sin sincronización en el tiempo: se escribe una sola vez.
class Voice::TimelineMirrorService
  def self.perform(call)
    new(call).perform
  end

  def initialize(call)
    @call = call
  end

  # @return [Message, nil] el activity creado, o nil si no hay dónde espejarlo.
  def perform
    conversation = mirror_conversation
    return nil unless conversation

    conversation.messages.create!(activity_params(conversation))
  end

  private

  attr_reader :call

  # Conversación ABIERTA del contacto en un inbox distinto al de Voz (la llamada).
  def mirror_conversation
    return nil unless call.contact

    call.contact.conversations
        .where(account_id: call.account_id, status: :open)
        .where.not(inbox_id: call.inbox_id)
        .order(last_activity_at: :desc)
        .first
  end

  def activity_params(conversation)
    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    }
  end

  def content
    I18n.t(
      'conversations.activity.voice_call.mirror',
      direction: direction_label,
      duration: duration_label,
      status: status_label
    )
  end

  def direction_label
    I18n.t("conversations.activity.voice_call.direction.#{call.direction}")
  end

  def duration_label
    seconds = call.duration_seconds.to_i
    format('%<min>dm %<sec>02ds', min: seconds / 60, sec: seconds % 60)
  end

  # completed → contestada; no_answer por ocupado → ocupado; no_answer → perdida;
  # resto → fallida. (Call no tiene estado 'busy'; se distingue por end_reason.)
  def status_label
    key = case call.status
          when 'completed' then 'answered'
          when 'no_answer' then call.end_reason.to_s.casecmp?('busy') ? 'busy' : 'missed'
          else 'failed'
          end
    I18n.t("conversations.activity.voice_call.status.#{key}")
  end
end

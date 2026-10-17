# La plataforma externa que replica WhatsApp para Auditoria empaqueta cada
# mensaje en bloques separados por "\r\n\r\n": tags opcionales (forwarded/
# reply), "type message: <tipo>" + "name file: <archivo>", el texto citado +
# el marcador "message:" en un reply, el texto real, y siempre "Source:
# <agente>" al final (+ el sufijo de "Sent from another device" si vino de
# la app externa). Nunca tocamos `content` -- las reglas de asignacion
# dependen de que el "Source:" literal siga ahi (ver Auditoria::
# AgentReconcilerService) -- todo lo calculado aqui se guarda aparte en
# content_attributes para que el frontend decida que mostrar.
class Auditoria::MessageAnnotatorService
  pattr_initialize [:message!]

  BLOCK_SEPARATOR = "\r\n\r\n".freeze
  SOURCE_PREFIX = 'Source: '.freeze
  DEVICE_SUFFIX = '✅ Sent from another device ✅'.freeze
  MESSAGE_MARKER = 'message:'.freeze
  TYPE_MESSAGE_LINE = /\Atype message: (\w+)/
  TAGS = %w[forwarded reply].freeze
  QUOTE_TYPE_TO_ATTACHMENT_TYPE = { 'image' => 'image', 'audio' => 'audio', 'video' => 'video', 'document' => 'file' }.freeze
  REPLY_SEARCH_WINDOW = 300

  def call
    return unless message.account.feature_enabled?('auditoria')

    blocks = strip_envelope(message.content.to_s.split(BLOCK_SEPARATOR))
    return unless blocks

    tag = blocks.first if TAGS.include?(blocks.first)
    blocks.shift if tag

    quoted_blocks, remaining_blocks = split_on_marker(blocks, tag)
    attrs = { 'auditoria_display_content' => reassemble(tag, strip_type_message(remaining_blocks)) }
    annotate_reply(tag, quoted_blocks, attrs)

    message.content_attributes = message.content_attributes.merge(attrs)
    message.save!
  end

  private

  # nil cuando el mensaje no trae el "Source: <agente>" final, es decir no
  # viene de la plataforma externa de Auditoria -- no se toca en absoluto.
  def strip_envelope(blocks)
    blocks.pop if blocks.last == DEVICE_SUFFIX
    return nil unless blocks.last&.start_with?(SOURCE_PREFIX)

    blocks.pop
    blocks
  end

  # Para un reply: intenta enlazar al mensaje real (hereda el cuadrito nativo
  # de cita con scroll-to, ver MessageList.vue/Base.vue). Si no se encuentra
  # con confianza, deja el texto citado para que el frontend lo muestre como
  # cita estatica sin link -- nunca inventa un enlace.
  def annotate_reply(tag, quoted_blocks, attrs)
    return unless tag == 'reply'

    quoted_text = strip_type_message(quoted_blocks).join(BLOCK_SEPARATOR)
    in_reply_to_id = resolve_reply(quoted_blocks, quoted_text)

    if in_reply_to_id
      message.in_reply_to = in_reply_to_id
    elsif quoted_text.present?
      attrs['auditoria_quoted_text'] = quoted_text
    end
  end

  def split_on_marker(blocks, tag)
    return [[], blocks] unless tag == 'reply'

    marker_index = blocks.index(MESSAGE_MARKER)
    return [[], blocks] unless marker_index

    [blocks[0...marker_index], blocks[(marker_index + 1)..] || []]
  end

  def strip_type_message(blocks)
    blocks.reject { |block| block.blank? || block.lines.first.to_s.match?(TYPE_MESSAGE_LINE) }
  end

  def reassemble(tag, blocks)
    parts = tag == 'forwarded' ? [tag, *blocks] : blocks
    parts.join(BLOCK_SEPARATOR)
  end

  # Busca, entre los mensajes anteriores de la misma conversacion, el que
  # coincide con el texto citado (ya limpio de Source/device) o, si el reply
  # era a un audio/imagen sin caption, el mas reciente con un adjunto del
  # mismo tipo. Es una heuristica: puede no encontrar nada, o -- si hay dos
  # mensajes identicos -- enlazar al equivocado.
  def resolve_reply(quoted_blocks, quoted_text)
    quoted_type = quoted_blocks.first.to_s[TYPE_MESSAGE_LINE, 1]

    prior_messages.find do |prior|
      if quoted_text.present?
        prior_display(prior).strip == quoted_text.strip
      elsif quoted_type
        prior.attachments.any? { |a| a.file_type == QUOTE_TYPE_TO_ATTACHMENT_TYPE[quoted_type] }
      end
    end&.id
  end

  def prior_display(prior)
    prior.content_attributes['auditoria_display_content'] || prior.content.to_s
  end

  def prior_messages
    message.conversation.messages.includes(:attachments)
           .where('messages.id < ?', message.id).order(id: :desc).limit(REPLY_SEARCH_WINDOW)
  end
end

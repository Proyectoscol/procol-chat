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
  # broadcast: false (usado por el backfill, rake auditoria:annotate_messages)
  # evita el save! normal -- que dispara "message.updated" por ActionCable y
  # reindexacion de busqueda por CADA mensaje -- y en su lugar escribe
  # content_attributes directo, sin esos callbacks. Para miles de mensajes
  # historicos de una sola corrida, ese enjambre de jobs de Sidekiq satura la
  # CPU sin que nadie este esperando el aviso en vivo. El hook en tiempo real
  # (un mensaje nuevo a la vez) si necesita el broadcast normal.
  pattr_initialize [:message!, { broadcast: true }]

  BLOCK_SEPARATOR = "\r\n\r\n".freeze
  SOURCE_PREFIX = 'Source: '.freeze
  DEVICE_SUFFIX = '✅ Sent from another device ✅'.freeze
  MESSAGE_MARKER = 'message:'.freeze
  TYPE_MESSAGE_LINE = /\Atype message: (\w+)/
  TAGS = %w[forwarded reply].freeze
  MULTIPLE_ADVISORS_LABEL_TITLE = 'auditoria-multiple-asesor'.freeze
  # content_attributes es `json` + `store coder: JSON` (ver Message) -- eso
  # serializa dos veces al guardar (el coder lo convierte a texto JSON, y la
  # columna nativa json lo vuelve a envolver en comillas), asi que en la base
  # queda como un string JSON escapado, no un objeto. Leerlo por Ruby/AR
  # deshace ambas capas sin que se note, pero el operador ->> de Postgres
  # sobre el valor crudo no puede sacar una clave de un string escalar --
  # hay que desenvolverlo primero con #>>'{}' y recien ahi castear a json.
  UNWRAP_CONTENT_ATTRIBUTES = "(content_attributes #>> '{}')::json".freeze

  def call
    return unless message.account.feature_enabled?('auditoria')

    blocks, source_name = strip_envelope(message.content.to_s.split(BLOCK_SEPARATOR))
    return unless blocks

    tag, quoted_blocks, remaining_blocks = parse_body(blocks)
    attrs = build_attrs(tag, quoted_blocks, remaining_blocks, source_name)

    message.content_attributes = message.content_attributes.merge(attrs)
    save_message
    flag_multiple_advisors if attrs['auditoria_source_user_id']
  end

  private

  def parse_body(blocks)
    tag = blocks.first if TAGS.include?(blocks.first)
    blocks.shift if tag

    quoted_blocks, remaining_blocks = split_on_marker(blocks, tag)
    [tag, quoted_blocks, remaining_blocks]
  end

  def build_attrs(tag, quoted_blocks, remaining_blocks, source_name)
    attrs = {
      'auditoria_display_content' => reassemble(tag, strip_type_message(remaining_blocks)),
      'auditoria_source_user_id' => resolve_source_user_id(source_name)
    }
    annotate_reply(tag, quoted_blocks, attrs)
    attrs
  end

  # Si la conversacion ya acumulo mensajes de mas de un asesor distinto
  # (tipico de un contacto interno al que dos asesores le escriben desde su
  # propio celular vinculado por QR), la marca con una label nativa para que
  # el equipo la vea en el panel lateral y el reporte de Auditoria la
  # excluya del calculo por asesor -- ninguno de los dos se queda con
  # metricas infladas o robadas por un numero que en realidad comparten.
  def flag_multiple_advisors
    conversation = message.conversation
    return if conversation.label_list.include?(MULTIPLE_ADVISORS_LABEL_TITLE)

    # reorder(nil): Message's default_scope orders by created_at, y Postgres
    # exige que las columnas de ORDER BY aparezcan en el SELECT cuando se usa
    # DISTINCT -- sin esto, explota con la misma clase de error que group().
    distinct_source_ids = conversation.messages
                                      .reorder(nil)
                                      .where("#{UNWRAP_CONTENT_ATTRIBUTES}->>'auditoria_source_user_id' IS NOT NULL")
                                      .distinct
                                      .pluck(Arel.sql("#{UNWRAP_CONTENT_ATTRIBUTES}->>'auditoria_source_user_id'"))
    return if distinct_source_ids.size <= 1

    label = Label.find_or_create_by!(account: message.account, title: MULTIPLE_ADVISORS_LABEL_TITLE) do |l|
      l.color = '#FB2C36'
      l.description = 'Conversacion con mensajes de mas de un asesor (Source distinto) - excluida de los reportes por asesor.'
    end
    conversation.add_labels(label.title)
  end

  def save_message
    return message.save! if broadcast

    # rubocop:disable Rails/SkipsModelValidations
    message.update_columns(content_attributes: message.content_attributes, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # nil cuando el mensaje no trae el "Source: <agente>" final, es decir no
  # viene de la plataforma externa de Auditoria -- no se toca en absoluto.
  def strip_envelope(blocks)
    blocks.pop if blocks.last == DEVICE_SUFFIX
    return nil unless blocks.last&.start_with?(SOURCE_PREFIX)

    [blocks, blocks.pop.delete_prefix(SOURCE_PREFIX)]
  end

  # Mismo match exacto (nombre completo, literal) que usa la regla de
  # asignacion "contains Source: <nombre>" -- si el nombre no calza con
  # ningun agente de la cuenta (tilde/espacio distinto, agente renombrado),
  # esta tambien queda nil; ver "reglas huerfanas" de reconcile_agents para
  # encontrar esos casos.
  def resolve_source_user_id(name)
    message.account.users.find_by(name: name)&.id
  end

  # Para un reply: NUNCA enlaza al mensaje real via in_reply_to -- se intento
  # (buscando el mensaje citado en la conversacion) pero el cuadrito nativo
  # de WhatsApp (Base.vue) muestra el `content` crudo del mensaje enlazado,
  # no la version limpia, y resolverlo cuando no esta en pantalla dispara un
  # fetch que mete ~200 mensajes de otro punto de la conversacion en el store
  # y desordena el feed. Siempre se deja como cita estatica (texto nomas).
  def annotate_reply(tag, quoted_blocks, attrs)
    return unless tag == 'reply'

    # Limpia ambos: si queda un in_reply_to_external_id viejo (de una corrida
    # anterior), ensure_in_reply_to (before_save) lo usa para re-resolver
    # in_reply_to por source_id y revive el enlace que justamente queremos
    # quitar.
    message.in_reply_to = nil
    message.in_reply_to_external_id = nil
    quoted_text = strip_type_message(quoted_blocks).join(BLOCK_SEPARATOR)
    attrs['auditoria_quoted_text'] = quoted_text if quoted_text.present?
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
end

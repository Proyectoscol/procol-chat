# Parsea el `_chat.txt` que trae cada export de WhatsApp (iOS o Android,
# ingles o espanol) en una lista de mensajes planos. No toca la base de
# datos ni sabe nada de contactos/conversaciones -- esa parte vive en el job
# de importacion. Aqui solo vive el riesgo real: el formato de texto varia
# por telefono/idioma y no hay manera de que truene a mitad de 1000 archivos
# por una linea rara, asi que todo lo que no se reconoce cae como texto
# plano en vez de abortar.
#
# Variantes de formato de linea que soporta:
#   iOS:     [18/07/25, 9:28:28 PM] Nombre: mensaje
#   Android: 18/07/25, 9:28 - Nombre: mensaje   (sin segundos, sin corchetes)
# En ambos casos puede venir con marcas invisibles (LRM/RLM, U+200E/U+200F)
# y un espacio angosto (U+202F) en vez de espacio normal antes de AM/PM.
#
# Devuelve un array de hashes:
#   { timestamp:, sender_name:, kind: :text | :attachment | :system,
#     body:, attachment_filename: }
# timestamp es un Time sin zona especifica (naive) -- quien llama decide en
# que zona interpretarlo (ver Import::WhatsappChatImportJob).
class Import::WhatsappChatTxtParser
  pattr_initialize [:raw_text!]

  INVISIBLE_CHARS = /[‎‏]/
  # El espacio entre la hora y AM/PM en los exports de iOS no es un espacio
  # normal -- es U+202F (narrow no-break space). Lo normalizamos a espacio
  # comun para que el regex de abajo no tenga que conocer ese detalle.
  NARROW_NBSP = / /

  IOS_LINE = %r{\A\[(?<date>\d{1,2}/\d{1,2}/\d{2,4}),\s*(?<time>\d{1,2}:\d{2}(?::\d{2})?(?:\s?[ap]\.?m\.?)?)\]\s(?<sender>[^:]+):\s(?<body>.*)\z}i
  ANDROID_LINE = %r{\A(?<date>\d{1,2}/\d{1,2}/\d{2,4}),\s*(?<time>\d{1,2}:\d{2}(?::\d{2})?(?:\s?[ap]\.?m\.?)?)\s-\s(?<sender>[^:]+):\s(?<body>.*)\z}i
  # Mensajes de sistema de WhatsApp que no tienen ":" (no van asociados a un
  # remitente) -- ej. "18/07/25, 9:28 - Los mensajes y las llamadas..."
  IOS_SYSTEM_LINE = %r{\A\[(?<date>\d{1,2}/\d{1,2}/\d{2,4}),\s*(?<time>\d{1,2}:\d{2}(?::\d{2})?(?:\s?[ap]\.?m\.?)?)\]\s(?<body>.*)\z}i
  ANDROID_SYSTEM_LINE = %r{\A(?<date>\d{1,2}/\d{1,2}/\d{2,4}),\s*(?<time>\d{1,2}:\d{2}(?::\d{2})?(?:\s?[ap]\.?m\.?)?)\s-\s(?<body>.*)\z}i

  # Dos formatos reales vistos en exports: el viejo "<attached: foo.jpg>" /
  # "<adjunto: foo.jpg>" (con el que se construyo y probo originalmente este
  # parser), y el que realmente trae WhatsApp en los exports actuales --
  # "foo.jpg (file attached)" / "foo.jpg (archivo adjunto)", el nombre
  # ANTES de la frase, entre parentesis, sin los dos puntos. Sin el segundo
  # patron, todo adjunto de un export reciente se pierde silenciosamente
  # (quedaba como texto plano, nunca marcado :attachment) -- hallazgo real
  # al importar los exports de 2026-11.
  ATTACHMENT_TOKEN_OLD = /<(?:attached|adjunto):\s*(.+?)>/i
  ATTACHMENT_TOKEN_NEW = /\A(.+?)\s*\((?:file attached|archivo adjunto)\)\z/i

  # Frases conocidas de mensajes de sistema (ingles/espanol) -- si el cuerpo
  # empieza con alguna de estas, se clasifica como :system en vez de :text.
  # Esta lista es best-effort: lo que no calce simplemente queda como texto
  # normal, nunca bloquea el import.
  SYSTEM_PHRASES = [
    /messages and calls are end-to-end encrypted/i,
    /los mensajes y las llamadas est[áa]n cifrados/i,
    /this message was deleted/i,
    /se elimin[óo] este mensaje/i,
    /you deleted this message/i,
    /eliminaste este mensaje/i,
    /missed voice call/i,
    /missed video call/i,
    /llamada de voz perdida/i,
    /llamada de video perdida/i,
    /created group/i,
    /cre[óo] el grupo/i,
    /changed the subject/i,
    /cambi[óo] el asunto/i,
    /image omitted/i,
    /imagen omitida/i,
    /video omitted/i,
    /video omitido/i,
    /gif omitted/i,
    /gif omitido/i,
    /audio omitted/i,
    /audio omitido/i,
    /sticker omitted/i,
    /sticker omitido/i,
    /contact card omitted/i,
    /tarjeta de contacto omitida/i,
    /document omitted/i,
    /documento omitido/i,
    # El nombre del contacto va en medio del mensaje ("Your security code
    # with Elie Merhy changed.") asi que estas no pueden anclarse al inicio
    # de la frase -- se buscan en cualquier parte del cuerpo.
    /security code with .+ changed/i,
    /c[óo]digo de seguridad (con|de) .+ cambi[óo]/i,
    /changed (their|to a new) phone number/i,
    /cambi[óo] (su número de tel[ée]fono|a un nuevo n[úu]mero)/i,
    /you blocked this contact/i,
    /bloqueaste a este contacto/i,
    /you unblocked this contact/i,
    /desbloqueaste a este contacto/i,
    /waiting for this message/i,
    /esperando este mensaje/i
  ].freeze

  def parse
    messages = []
    normalized_lines.each do |line|
      if (parsed = parse_line(line))
        messages << parsed
      elsif messages.any?
        # Linea de continuacion (mensaje multilinea, ej. un texto con salto
        # de linea) -- se pega al mensaje anterior en vez de perderse o
        # crear un mensaje nuevo sin remitente.
        messages.last[:body] = "#{messages.last[:body]}\n#{line}"
      end
      # Si no matchea nada y no hay mensaje previo (primera linea rara de un
      # archivo), se descarta -- no hay donde pegarla.
    end
    messages.each { |message| classify_system_message!(message) }
    messages
  end

  private

  def normalized_lines
    raw_text
      .gsub(INVISIBLE_CHARS, '')
      .gsub(NARROW_NBSP, ' ')
      .split(/\r?\n/)
  end

  def parse_line(line)
    if (match = line.match(IOS_LINE)) || (match = line.match(ANDROID_LINE))
      build_message(match, kind: :text)
    elsif (match = line.match(IOS_SYSTEM_LINE)) || (match = line.match(ANDROID_SYSTEM_LINE))
      build_system_message(match)
    end
  end

  def build_message(match, kind:)
    body = match[:body]
    attachment_filename = extract_attachment_filename(body)
    {
      timestamp: parse_timestamp(match[:date], match[:time]),
      sender_name: match[:sender].strip,
      kind: attachment_filename ? :attachment : kind,
      body: body,
      attachment_filename: attachment_filename
    }
  end

  def extract_attachment_filename(body)
    old_match = body.match(ATTACHMENT_TOKEN_OLD)
    return old_match[1].strip if old_match

    new_match = body.match(ATTACHMENT_TOKEN_NEW)
    new_match && new_match[1].strip
  end

  def build_system_message(match)
    {
      timestamp: parse_timestamp(match[:date], match[:time]),
      sender_name: nil,
      kind: :system,
      body: match[:body],
      attachment_filename: nil
    }
  end

  def classify_system_message!(message)
    return if message[:kind] == :attachment
    return unless SYSTEM_PHRASES.any? { |phrase| message[:body] =~ phrase }

    message[:kind] = :system
  end

  # Fecha SIEMPRE dia/mes/anio (locale del negocio) -- WhatsApp no incluye
  # zona horaria ni indicador de orden, asi que esto es una convencion fija,
  # no una deteccion.
  def parse_timestamp(date_part, time_part)
    day, month, year = date_part.split('/').map(&:to_i)
    year += year < 100 ? 2000 : 0
    # rubocop:disable Rails/TimeZone -- a proposito sin zona: este parser no
    # sabe en que zona horaria estaba el telefono que exporto el chat, eso
    # lo decide quien llama (ver Import::WhatsappChatImportJob).
    Time.new(year, month, day) + seconds_from_midnight(time_part)
    # rubocop:enable Rails/TimeZone
  rescue ArgumentError
    nil
  end

  MERIDIEM = /[ap]\.?m\.?/i

  def seconds_from_midnight(time_part)
    meridiem = time_part[MERIDIEM]
    digits = time_part.sub(/\s?#{MERIDIEM}/o, '').split(':').map(&:to_i)
    hour, minute, second = digits
    second ||= 0
    hour = to_24_hour(hour, meridiem)
    (hour * 3600) + (minute * 60) + second
  end

  def to_24_hour(hour, meridiem)
    return hour if meridiem.blank?

    if meridiem.downcase.start_with?('a')
      hour == 12 ? 0 : hour
    else
      hour == 12 ? 12 : hour + 12
    end
  end
end

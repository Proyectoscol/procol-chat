# Parsea el texto de un archivo .vcf (RFC 2426) a los datos minimos que
# necesita un Attachment file_type: :contact (mismo shape que
# Whatsapp::IncomingMessageBaseService#attach_contact usa para el JSON
# estructurado de contactos de la Cloud API, para que ambos canales
# rendericen con la misma burbuja Contact.vue sin tocar frontend).
#
# Soporta varios vcards concatenados en un solo archivo (WhatsApp permite
# compartir varios contactos a la vez) y lineas plegadas (RFC 2425: una
# linea que empieza con espacio o tab es continuacion de la anterior, usado
# por ejemplo para fotos en BASE64 largas).
class Twilio::VcardContactParserService
  pattr_initialize [:text!]

  def call
    vcards.map { |lines| contact_from(lines) }
  end

  private

  def vcards
    unfolded_lines.each_with_object([]) do |line, cards|
      cards << [] if line.match?(/\ABEGIN:VCARD\z/i)
      cards.last << line if cards.any?
    end
  end

  def unfolded_lines
    text.to_s.split(/\r\n|\r|\n/).each_with_object([]) do |line, acc|
      if line.start_with?(' ', "\t") && acc.any?
        acc[-1] += line[1..]
      else
        acc << line
      end
    end
  end

  def contact_from(lines)
    properties = lines.filter_map { |line| parse_property(line) }
    { name: name_from(properties), phones: phones_from(properties) }
  end

  # "item1.TEL;waid=573132620802:+57 313 2620802" -> name: "TEL",
  # value: "+57 313 2620802" -- el grupo "item1." y los parametros
  # (waid=..., type=...) no importan para lo que se necesita mostrar.
  def parse_property(line)
    name_and_params, _, value = line.partition(':')
    return nil if value.blank?

    { name: name_and_params.split(';').first.to_s.split('.').last.upcase, value: value.strip }
  end

  def name_from(properties)
    fn = properties.find { |p| p[:name] == 'FN' }&.fetch(:value, nil)
    fn.presence || name_from_n(properties)
  end

  # Fallback si no hay FN: N es "Apellido;Nombre;Segundo nombre;Prefijo;Sufijo".
  def name_from_n(properties)
    n_value = properties.find { |p| p[:name] == 'N' }&.fetch(:value, nil)
    return if n_value.blank?

    last, first, = n_value.split(';')
    [first, last].filter_map(&:presence).join(' ').presence
  end

  def phones_from(properties)
    properties.select { |p| p[:name] == 'TEL' }.pluck(:value)
  end
end

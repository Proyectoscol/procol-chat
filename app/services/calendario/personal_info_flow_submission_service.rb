# Procesa la respuesta de la plantilla twilio/flows "solicitud_
# informacion_personal" (ver espacio-trabajo/.../create_personal_info_flow_
# template.rb) y actualiza el contacto automaticamente.
#
# Twilio::InteractiveMessageParser ya guarda el JSON crudo en
# message.content_attributes['interactive_data'] = { 'pages' => [{ 'items'
# => [{ 'label' => ..., 'value' => ... }] }] }. Esta clase solo se activa si
# reconoce AL MENOS un label propio del formulario (nunca toca el contacto
# por un Flow distinto que no conozca).
#
# Los SINGLE_SELECT (tipo de documento, EPS) pueden volver con el "id" de
# la opcion o con su "title" visible -- la docs de Twilio no lo deja claro,
# asi que se intentan ambos antes de rendirse. Si no se puede resolver algo
# con certeza, se deja una nota privada con el valor crudo en vez de
# adivinar y guardar un dato incorrecto en la historia clinica.
class Calendario::PersonalInfoFlowSubmissionService
  pattr_initialize [:message!]

  LABEL_FIRST_NAME = 'Primer nombre'.freeze
  LABEL_SECOND_NAME = 'Segundo nombre'.freeze
  LABEL_FIRST_LAST_NAME = 'Primer apellido'.freeze
  LABEL_SECOND_LAST_NAME = 'Segundo apellido'.freeze
  LABEL_DOCUMENT_TYPE = 'Tipo de documento'.freeze
  LABEL_DOCUMENT_NUMBER = 'Número de documento'.freeze
  LABEL_SECONDARY_PHONE = 'Un segundo número de contacto'.freeze
  LABEL_DATE_OF_BIRTH = 'Fecha de nacimiento'.freeze
  LABEL_BIRTH_CITY = 'Lugar de nacimiento'.freeze
  LABEL_ADDRESS = 'Dirección'.freeze
  LABEL_PAYER = 'Entidad / EPS'.freeze

  RECOGNIZED_LABELS = [
    LABEL_FIRST_NAME, LABEL_SECOND_NAME, LABEL_FIRST_LAST_NAME, LABEL_SECOND_LAST_NAME, LABEL_DOCUMENT_TYPE,
    LABEL_DOCUMENT_NUMBER, LABEL_SECONDARY_PHONE, LABEL_DATE_OF_BIRTH, LABEL_BIRTH_CITY, LABEL_ADDRESS, LABEL_PAYER
  ].freeze

  DOCUMENT_TYPE_TITLES = {
    'cédula de ciudadanía' => 'cc', 'tarjeta de identidad' => 'ti', 'cédula de extranjería' => 'ce',
    'pasaporte' => 'pa', 'registro civil' => 'rc', 'permiso especial de permanencia' => 'pep',
    'permiso de protección temporal' => 'ppt'
  }.freeze

  def perform
    return unless flow_submission?

    contact.assign_attributes(contact_attributes)
    apply_payer
    contact.save!
    note_unresolved_payer if @unresolved_payer_value
  end

  private

  def contact
    @contact ||= message.conversation.contact
  end

  def account
    @account ||= message.account
  end

  def items
    @items ||= (message.content_attributes['interactive_data'] || {})['pages'].to_a.flat_map { |page| page['items'] || [] }
  end

  def value_for(label)
    items.find { |item| item['label'] == label }&.dig('value')
  end

  def flow_submission?
    items.any? { |item| RECOGNIZED_LABELS.include?(item['label']) }
  end

  def full_name
    [value_for(LABEL_FIRST_NAME), value_for(LABEL_SECOND_NAME), value_for(LABEL_FIRST_LAST_NAME),
     value_for(LABEL_SECOND_LAST_NAME)].compact_blank.join(' ')
  end

  def document_type
    raw = value_for(LABEL_DOCUMENT_TYPE).to_s.downcase.strip
    return raw if Contact.document_types.key?(raw)

    DOCUMENT_TYPE_TITLES[raw]
  end

  def contact_attributes
    {
      name: full_name.presence || contact.name,
      document_type: document_type,
      identifier: value_for(LABEL_DOCUMENT_NUMBER).presence || contact.identifier,
      secondary_phone_number: value_for(LABEL_SECONDARY_PHONE).presence || contact.secondary_phone_number,
      custom_attributes: contact.custom_attributes.merge(custom_attribute_updates),
      additional_attributes: contact.additional_attributes.merge(additional_attribute_updates)
    }.compact
  end

  def custom_attribute_updates
    {
      'date_of_birth' => value_for(LABEL_DATE_OF_BIRTH),
      'address' => value_for(LABEL_ADDRESS)
    }.compact_blank
  end

  def additional_attribute_updates
    { 'city' => value_for(LABEL_BIRTH_CITY) }.compact_blank
  end

  def apply_payer
    raw = value_for(LABEL_PAYER)
    return if raw.blank?
    return if raw.to_s == 'otra'

    payer = account.calendario_payers.find_by(id: raw) || account.calendario_payers.find_by(name: raw)
    if payer
      contact.payer_id = payer.id
    else
      @unresolved_payer_value = raw
    end
  end

  def note_unresolved_payer
    message.conversation.messages.create!(
      account: account, inbox: message.inbox, private: true, message_type: :outgoing,
      content: '⚠️ El paciente respondió el formulario de datos personales con una EPS que no se pudo identificar ' \
               "automáticamente (valor recibido: #{@unresolved_payer_value.inspect}). Asígnala manualmente en el contacto."
    )
  end
end

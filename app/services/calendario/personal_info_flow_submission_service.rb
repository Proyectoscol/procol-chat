# Procesa la respuesta de la plantilla twilio/flows "solicitud_
# informacion_personal" (ver espacio-trabajo/.../create_personal_info_flow_
# template.rb) y actualiza el contacto automaticamente.
#
# Confirmado con un envio real 2026-11-27 (conversacion #366):
# message.content_attributes['interactive_data']['pages'] es un array de
# { 'pageId' => <id de la pagina>, 'items' => [{ 'label' => <name del
# campo>, 'value' => <valor> }] } -- OJO: 'label' aqui NO es el texto
# visible que se definio ("Lugar de nacimiento"), es el atributo "name"
# del layout del Flow (p. ej. "ciudad_nacimiento"). 'flow_data' tambien
# llega pero como un STRING con JSON anidado por pagina -- 'interactive_
# data' ya viene parseado y es mas simple de leer, por eso se usa este.
class Calendario::PersonalInfoFlowSubmissionService
  pattr_initialize [:message!]

  FIELD_NAMES = %w[
    primer_nombre segundo_nombre primer_apellido segundo_apellido tipo_documento numero_documento
    telefono_secundario fecha_nacimiento ciudad_nacimiento direccion payer_id
  ].freeze

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

  def items_by_name
    pages = message.content_attributes.dig('interactive_data', 'pages') || []
    @items_by_name ||= pages.flat_map { |page| page['items'] || [] }.each_with_object({}) do |item, acc|
      acc[item['label']] = item['value']
    end
  end

  def flow_submission?
    FIELD_NAMES.any? { |name| items_by_name.key?(name) }
  end

  def full_name
    %w[primer_nombre segundo_nombre primer_apellido segundo_apellido].filter_map { |n| items_by_name[n] }.compact_blank.join(' ')
  end

  def document_type
    raw = items_by_name['tipo_documento'].to_s.downcase.strip
    raw if Contact.document_types.key?(raw)
  end

  def contact_attributes
    {
      name: full_name.presence || contact.name,
      document_type: document_type,
      identifier: items_by_name['numero_documento'].presence || contact.identifier,
      secondary_phone_number: items_by_name['telefono_secundario'].presence || contact.secondary_phone_number,
      custom_attributes: contact.custom_attributes.merge(custom_attribute_updates),
      additional_attributes: contact.additional_attributes.merge(additional_attribute_updates)
    }.compact
  end

  def custom_attribute_updates
    {
      'date_of_birth' => items_by_name['fecha_nacimiento'],
      'address' => items_by_name['direccion']
    }.compact_blank
  end

  def additional_attribute_updates
    { 'city' => items_by_name['ciudad_nacimiento'] }.compact_blank
  end

  # El id de la opcion del SINGLE_SELECT de EPS es el payer_id REAL (ver
  # script de creacion de la plantilla) -- nunca se adivina por nombre.
  def apply_payer
    raw = items_by_name['payer_id']
    return if raw.blank?
    return if raw.to_s == 'otra'

    payer = account.calendario_payers.find_by(id: raw)
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

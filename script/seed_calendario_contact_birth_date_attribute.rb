# Crea el custom attribute "Fecha de nacimiento" en contactos -- no existe
# ningun campo nativo para esto en Chatwoot (ver Contact#schema), y hace
# falta para el flujo de "crear contacto desde un mensaje" (modal
# ContactFromMessageModal.vue) que intenta pre-llenarlo cuando el texto del
# mensaje la menciona explicitamente.
#
# Idempotente: correrlo de nuevo no duplica la definicion (unique index en
# attribute_key+attribute_model+account_id).
Account.find_each do |account|
  CustomAttributeDefinition.find_or_create_by!(
    attribute_key: 'date_of_birth',
    attribute_model: :contact_attribute,
    account: account
  ) do |definition|
    definition.attribute_display_name = 'Fecha de nacimiento'
    definition.attribute_display_type = :date
    definition.attribute_description = 'Fecha de nacimiento del paciente (si se conoce).'
  end
end

puts "Custom attribute 'date_of_birth' asegurado en #{Account.count} cuenta(s)."

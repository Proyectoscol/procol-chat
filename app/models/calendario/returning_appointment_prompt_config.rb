# Configuracion por bandeja del mensaje de "paciente que regresa" (ver
# Calendario::ReturningAppointmentPromptListener) -- editable desde la UI
# en Mensajeria para que el usuario pueda activarlo/ajustarlo en produccion
# sin tocar codigo. `active: false` (default) apaga el listener por
# completo para esa bandeja; `test_mode: true` (default) lo deja mandar
# solo una nota privada de prueba en vez de un mensaje real, mismo patron
# de seguridad que Calendario::AppointmentEventTrigger#test_mode.
class Calendario::ReturningAppointmentPromptConfig < ApplicationRecord
  self.table_name = 'calendario_returning_appointment_prompt_configs'

  DEFAULT_ASK_TEMPLATE =
    'Hola nuevamente. Esta nueva solicitud es respecto de tu próxima cita ' \
    'el {{ appointment.date }} a las {{ appointment.time }} con {{ appointment.professional_name }} ' \
    '({{ appointment.service_name }}).'.freeze
  DEFAULT_OPTIONS = ['Sí, cancelar cita', 'Sí, reagendar', 'Hablar con recepción'].freeze

  belongs_to :account
  belongs_to :inbox

  validates :inbox_id, uniqueness: true
  validate :inbox_belongs_to_account

  # Mismo patron que Calendario::WelcomeBotAppointmentActions#resolved_text:
  # la version activa de la key de la biblioteca manda sobre el texto
  # literal guardado aqui, que a su vez manda sobre el default de codigo.
  def resolved_ask_template
    library_text = message_template_key.present? ? Calendario::MessageTemplate.active_body(account, message_template_key) : nil
    library_text.presence || ask_template.presence || DEFAULT_ASK_TEMPLATE
  end

  def resolved_options
    options.presence || DEFAULT_OPTIONS
  end

  private

  def inbox_belongs_to_account
    return if inbox.blank? || inbox.account_id == account_id

    errors.add(:inbox, :invalid)
  end
end

# Envia manualmente la plantilla "solicitud_informacion_personal"
# (twilio/flows, ver espacio-trabajo/.../create_personal_info_flow_
# template.rb) al contacto de una conversacion -- boton "Solicitar datos"
# en el panel de contacto. El content_sid queda fijo aqui porque es una
# sola plantilla, de uso puntual -- si se vuelve a crear una version nueva
# en Twilio, se actualiza este valor.
class Calendario::SendPersonalInfoFlowService
  CONTENT_SID = 'HXd20b398942befc990462e2b5ac8cdd0b'.freeze

  pattr_initialize [:conversation!]

  def perform
    return { success: false, error: 'El contacto no tiene teléfono' } if conversation.contact.phone_number.blank?

    message = build_message
    result = Twilio::SendOnTwilioService.new(message: message).send_csat_template_message(
      phone_number: conversation.contact_inbox.source_id, content_sid: CONTENT_SID
    )
    apply_send_result(message, result)
    result
  end

  private

  def build_message
    conversation.messages.build(
      account: conversation.account, inbox: conversation.inbox, message_type: :outgoing,
      content: 'Solicitud de información personal', content_attributes: { skip_send_reply: true }
    )
  end

  def apply_send_result(message, result)
    success = result[:success].present?
    message.source_id = result[:message_id] if success && result[:message_id].present?
    message.status = :failed unless success
    message.save!
  end
end

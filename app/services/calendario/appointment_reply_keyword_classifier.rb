# Compartido entre Calendario::NoShowReplyListener y
# Calendario::ReturningAppointmentPromptListener -- ambos reaccionan a la
# respuesta de texto libre de un paciente sobre su cita (reprogramar vs
# cancelar), con las mismas palabras clave. Ver el comentario de clase de
# NoShowReplyListener para por que se hace match por texto en vez de un
# "payload" de boton.
module Calendario::AppointmentReplyKeywordClassifier
  RESCHEDULE_KEYWORDS = %w[reprogramar reagendar].freeze
  CANCEL_KEYWORDS = %w[cancelar].freeze

  def classify_appointment_reply(content)
    normalized = content.to_s.downcase.unicode_normalize(:nfkd).gsub(/[^\x00-\x7F]/, '')
    return :reschedule if RESCHEDULE_KEYWORDS.any? { |word| normalized.include?(word) }
    return :cancel if CANCEL_KEYWORDS.any? { |word| normalized.include?(word) }

    nil
  end
end

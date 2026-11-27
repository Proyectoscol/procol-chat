# Usado por Calendario::NoShowReplyListener -- reacciona a la respuesta de
# texto libre de un paciente sobre su cita (reprogramar vs cancelar). Ver
# el comentario de clase de NoShowReplyListener para por que se hace match
# por texto en vez de un "payload" de boton.
module Calendario::AppointmentReplyKeywordClassifier
  RESCHEDULE_KEYWORDS = %w[reprogramar reagendar].freeze
  CANCEL_KEYWORDS = %w[cancelar].freeze

  # Bug real encontrado en auditoria con Codex 2026-11-27: un `include?` por
  # substring clasificaba cualquier frase que CONTUVIERA la palabra como la
  # intencion opuesta -- "No quiero cancelar mi cita" cancelaba la cita igual
  # que un simple "Cancelar". El boton real solo manda su etiqueta exacta
  # ("Reprogramar"/"Cancelar", ver comentario de clase de NoShowReplyListener),
  # asi que el match debe ser por igualdad (recortando espacios), no
  # contencion.
  def classify_appointment_reply(content)
    normalized = content.to_s.strip.downcase.unicode_normalize(:nfkd).gsub(/[^\x00-\x7F]/, '')
    return :reschedule if RESCHEDULE_KEYWORDS.include?(normalized)
    return :cancel if CANCEL_KEYWORDS.include?(normalized)

    nil
  end
end

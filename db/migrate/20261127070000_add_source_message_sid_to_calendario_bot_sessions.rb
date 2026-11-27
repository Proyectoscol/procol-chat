# Bug real encontrado en auditoria con Codex 2026-11-27 (hallazgo #6): un
# boton viejo de WhatsApp (ej. "Confirmar" de un recordatorio de una cita ya
# resuelta) podia terminar accionando la sesion ACTIVA de una cita distinta
# y mas reciente en la misma conversacion -- no habia forma de saber a que
# mensaje exacto estaba respondiendo el paciente. source_message_sid guarda
# el SID de Twilio del mensaje que la sesion esta esperando que respondan,
# para cruzarlo contra OriginalRepliedMessageSid del webhook entrante.
class AddSourceMessageSidToCalendarioBotSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :calendario_bot_sessions, :source_message_sid, :string
  end
end

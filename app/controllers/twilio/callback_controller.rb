class Twilio::CallbackController < ApplicationController
  def create
    Webhooks::TwilioEventsJob.perform_later(permitted_params.to_unsafe_hash)

    head :no_content
  end

  private

  def permitted_params # rubocop:disable Metrics/MethodLength
    params.permit(
      :ApiVersion,
      :SmsSid,
      :From,
      :ToState,
      :ToZip,
      :AccountSid,
      :MessageSid,
      :FromCountry,
      :ToCity,
      :FromCity,
      :To,
      :FromZip,
      :Body,
      :ToCountry,
      :FromState,
      *Array.new(10) { |i| :"MediaUrl#{i}" },
      *Array.new(10) { |i| :"MediaContentType#{i}" },
      :MessagingServiceSid,
      :NumMedia,
      :Latitude,
      :Longitude,
      :MessageType,
      :ProfileName,
      :ExternalUserId,
      :ParentExternalUserId,
      :ProfileUsername,
      :Username,
      :FlowData,
      :InteractiveData,
      # Bug real encontrado en auditoria con Codex 2026-11-27 (hallazgo #6):
      # Twilio manda este campo cuando el paciente responde a un mensaje
      # especifico de WhatsApp (incluye el tap de un boton quick-reply de
      # una plantilla), pero no estaba en el whitelist -- sin el, era
      # imposible saber a que mensaje exacto respondia un boton, y un
      # boton viejo podia accionar la sesion activa de una cita distinta.
      :OriginalRepliedMessageSid
    )
  end
end

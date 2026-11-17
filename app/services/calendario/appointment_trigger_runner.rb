# Envia la plantilla de un Calendario::AppointmentEventTrigger para una cita
# puntual. Deliberadamente NO hereda de ActionService/AutomationRules::ActionService
# (ver addendum del 2026-10-29 al eng-review): esos dos quedan atados a
# @conversation via Messages::MessageBuilder y no tienen forma de elegir
# canal/plantilla explicitos. Este runner sigue el patron de
# Whatsapp::OneoffCampaignService en cambio: inbox + contacto, sin conversacion.
class Calendario::AppointmentTriggerRunner
  pattr_initialize [:trigger!, :appointment!]

  def perform
    return :already_fired if already_fired?
    return :inactive unless trigger.active? && appointment_still_applies?
    return :no_phone if appointment.contact.phone_number.blank?

    send_template_message
    record_firing!
    :sent
  end

  private

  delegate :inbox, to: :trigger
  delegate :channel, to: :inbox

  def already_fired?
    Calendario::AppointmentTriggerFiring.exists?(trigger_id: trigger.id, appointment_id: appointment.id)
  end

  # Para before_start: si ya se confirmo/atendio/cancelo/no-show desde que se
  # encolo el recordatorio, ya no aplica -- esto es lo que detiene la
  # escalera de recordatorios sin necesitar cancelar el ActiveJob encolado
  # (no hay forma nativa de cancelarlo en este stack; el guard en el momento
  # de ejecutar es el patron ya usado en el resto del codebase).
  def appointment_still_applies?
    return true unless trigger.before_start?

    appointment.pending? || appointment.confirmed?
  end

  def send_template_message
    processed = Calendario::AppointmentLiquidTemplateProcessorService.new(appointment: appointment, inbox: inbox)
                                                                       .process_template_params(trigger.template_params)
    return if processed.blank?

    processor = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: processed)
    name, namespace, lang_code, parameters = processor.call
    return if name.blank?

    channel.send_template(appointment.contact.phone_number, {
                             name: name, namespace: namespace, lang_code: lang_code, parameters: parameters
                           }, nil)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: appointment.account).capture_exception
  end

  def record_firing!
    Calendario::AppointmentTriggerFiring.create!(trigger: trigger, appointment: appointment, fired_at: Time.current)
  end
end

# Logica de waitlist externalizada del modelo Calendario::Appointment (que ya
# tiene 8 callbacks) -- mismo principio que AppointmentEventTrigger/
# AppointmentTriggerRunner: lo que pasa al crear/cancelar una cita vive en un
# service explicito, llamado desde donde ya se sabe si la cita se guardo bien
# (nunca bloquea el booking si falla).
class Calendario::WaitlistFulfillmentService
  pattr_initialize [:appointment!]

  def fulfill!
    entry = account.calendario_waitlist_entries.pending.find_by(
      contact_id: appointment.contact_id, professional_id: appointment.professional_id, service_id: appointment.service_id
    )
    entry&.update!(status: :fulfilled, fulfilled_by_appointment: appointment)
  rescue => e
    Rails.logger.error("Calendario::WaitlistFulfillmentService#fulfill! failed for appointment #{appointment.id}: #{e.message}")
  end

  # Cancelacion temporal: la cita vuelve a necesitar fecha, sin saber cuando.
  # origin: :cancellation en ambas ramas -- el personal necesita distinguir
  # "alguien nuevo que agregue a mano" de "alguien que ya tenia cita y se
  # enfermo", sin importar si la entrada de waitlist era nueva o se reusaba.
  def reactivate!
    entry = account.calendario_waitlist_entries.find_by(fulfilled_by_appointment_id: appointment.id)
    if entry
      entry.update!(status: :pending, fulfilled_by_appointment: nil, origin: :cancellation)
    else
      account.calendario_waitlist_entries.create!(
        contact: appointment.contact, professional: appointment.professional, service: appointment.service,
        status: :pending, origin: :cancellation
      )
    end
  rescue => e
    Rails.logger.error("Calendario::WaitlistFulfillmentService#reactivate! failed for appointment #{appointment.id}: #{e.message}")
  end

  private

  def account
    appointment.account
  end
end

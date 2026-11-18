class Calendario::AppointmentDrop < BaseDrop
  def starts_at
    Calendario::SpanishDateFormatter.long_date_time(@obj.starts_at.in_time_zone(zone))
  end

  def date
    Calendario::SpanishDateFormatter.long_date(@obj.starts_at.in_time_zone(zone))
  end

  def time
    @obj.starts_at.in_time_zone(zone).strftime('%I:%M %p')
  end

  # Solo tiene valor mientras corre un trigger on_reschedule (ver
  # Calendario::Appointment#run_on_reschedule_triggers) -- '' en cualquier
  # otro momento para que un trigger mal configurado con esta variable no
  # reviente el render en vez de solo mostrar vacio.
  def previous_date
    return '' if @obj.rescheduled_from.blank?

    Calendario::SpanishDateFormatter.long_date(@obj.rescheduled_from.in_time_zone(zone))
  end

  def previous_time
    return '' if @obj.rescheduled_from.blank?

    @obj.rescheduled_from.in_time_zone(zone).strftime('%I:%M %p')
  end

  def service_name
    @obj.service.name
  end

  def professional_name
    @obj.professional.name
  end

  def status
    @obj.status
  end

  private

  def zone
    @obj.account.reporting_timezone.presence || 'UTC'
  end
end

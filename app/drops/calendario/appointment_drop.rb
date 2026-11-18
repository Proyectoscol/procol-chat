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

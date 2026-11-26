# Capa Calendario sobre el horario laboral nativo de Chatwoot
# (Inbox#out_of_office?, WorkingHour) -- agrega dos cosas que esa feature no
# sabe: festivos colombianos reales (gema `holidays`, incluye Semana Santa y
# los que se corren al lunes por la Ley Emiliani) y excepciones puntuales
# (Calendario::WorkingDayOverride, para "este festivo SI se trabaja" o lo
# contrario). Usar esto en vez de `inbox.out_of_office?` / `WorkingHour`
# directo en cualquier logica de Calendario que dependa de si hay alguien
# atendiendo.
class Calendario::BusinessHours
  pattr_initialize [:inbox!]

  def open_at?(time = Time.current)
    return false unless inbox.working_hours_enabled?

    date = local_date(time)
    return false if closed_all_day_on?(date)

    within_hours_on?(date, time)
  end

  def closed_at?(time = Time.current)
    !open_at?(time)
  end

  # Hora de cierre para una fecha dada (zona del inbox) -- nil si ese dia
  # esta cerrado todo el dia (fin de semana, festivo, override cerrado).
  # Pensado para "ya paso la hora de cierre de este dia sin que
  # respondieran" (ver Calendario::WelcomeBotListener), no para "ahora
  # mismo" (eso es open_at?/closed_at?).
  def close_time_on(date)
    return nil unless inbox.working_hours_enabled?
    return nil if closed_all_day_on?(date)

    working_hour = working_hour_for(date)
    date.in_time_zone(zone).change(hour: working_hour.close_hour, min: working_hour.close_minutes)
  end

  private

  def closed_all_day_on?(date)
    override = override_for(date)
    return !override.open? if override.present?
    return true if holiday?(date)

    working_hour = working_hour_for(date)
    working_hour.blank? || working_hour.closed_all_day?
  end

  def within_hours_on?(date, time)
    working_hour = working_hour_for(date)
    return true if working_hour.open_all_day?

    local = time.in_time_zone(zone)
    open_time = date.in_time_zone(zone).change(hour: working_hour.open_hour, min: working_hour.open_minutes)
    close_time = date.in_time_zone(zone).change(hour: working_hour.close_hour, min: working_hour.close_minutes)
    local.between?(open_time, close_time)
  end

  def override_for(date)
    inbox.calendario_working_day_overrides.find_by(date: date)
  end

  def holiday?(date)
    Holidays.on(date, :co).present?
  end

  def working_hour_for(date)
    inbox.working_hours.find_by(day_of_week: date.wday)
  end

  def local_date(time)
    time.in_time_zone(zone).to_date
  end

  def zone
    inbox.timezone.presence || 'UTC'
  end
end

# Agrupa en Ruby (no en SQL) para evitar el bug de timezone ya conocido en
# este codebase (ver Auditoria/Sentimiento): starts_at se guarda en UTC, pero
# "que dia fue" tiene que decidirse en la zona de la cuenta, no en la del
# servidor de Postgres. El volumen de citas de un consultorio no justifica
# optimizar esto con date_trunc en SQL.
class Calendario::AppointmentStatsService
  # "until" es palabra reservada de Ruby -- no puede ser nombre de metodo/
  # variable local, de ahi range_since/range_until en vez de since/until.
  #
  # group_by decide sobre que fecha se arma el desglose por dia:
  #   - "starts_at" (default): para que dia quedo agendada la cita -- la
  #     vista de siempre, "volumen de citas por dia de atencion".
  #   - "created_at": que dia se CREO el registro -- para auditoria ("que
  #     dia se reservaron mas citas", independiente de para cuando haya
  #     quedado cada una). El rango (range_since/range_until) tambien se
  #     aplica sobre esa misma columna en este modo, no sobre starts_at.
  pattr_initialize [:account!, { range_since: nil, range_until: nil, professional_id: nil, group_by: 'starts_at' }]

  STATUSES = %w[pending confirmed attended no_show cancelled].freeze

  def perform
    { days: days, summary: summary }
  end

  private

  def zone
    @zone ||= ActiveSupport::TimeZone[account.reporting_timezone.presence || 'UTC']
  end

  def date_column
    group_by == 'created_at' ? :created_at : :starts_at
  end

  def appointments
    @appointments ||= begin
      scope = account.calendario_appointments.where(date_column => range_since..range_until)
      scope = scope.where(professional_id: professional_id) if professional_id.present?
      scope.to_a
    end
  end

  def days
    grouped = appointments.group_by { |appointment| appointment.public_send(date_column).in_time_zone(zone).to_date }
    grouped.keys.sort.map do |date|
      day_appointments = grouped[date]
      counts = STATUSES.index_with { |status| day_appointments.count { |a| a.status == status } }
      { date: date.iso8601, total: day_appointments.size, **counts }
    end
  end

  def summary
    total = appointments.size
    day_count = days.size

    {
      total: total,
      avg_per_day: day_count.positive? ? (total.to_f / day_count).round(1) : 0,
      attended_pct: percentage_of('attended', total),
      no_show_pct: percentage_of('no_show', total),
      cancelled_pct: percentage_of('cancelled', total)
    }
  end

  def percentage_of(status, total)
    return 0 unless total.positive?

    (appointments.count { |a| a.status == status } * 100.0 / total).round(1)
  end
end

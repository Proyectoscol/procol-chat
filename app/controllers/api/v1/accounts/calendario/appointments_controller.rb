class Api::V1::Accounts::Calendario::AppointmentsController < Api::V1::Accounts::BaseController
  wrap_parameters :appointment, include: %i[professional_id service_id contact_id conversation_id starts_at ends_at status notes force]

  before_action :check_authorization
  before_action :fetch_appointment, only: [:show, :update]

  rescue_from Calendario::AppointmentWarningsError, with: :render_appointment_warnings

  def index
    render json: filtered_appointments.order(starts_at: :desc).map { |appointment| serialize(appointment) }
  end

  def show
    render json: serialize(@appointment).merge(history: history_for(@appointment))
  end

  def agenda
    # "Hoy" tiene que decidirse en la zona del consultorio, no en la del
    # servidor -- Date.current/for_day usan Time.zone (UTC por defecto), lo
    # que recorta o adelanta la agenda unas horas en America/Bogota. ?date
    # opcional reusa este mismo endpoint para "siguiente dia con citas" (ver
    # #next_agenda_date) en vez de duplicar el include/serialize de arriba.
    appointments = Current.account.calendario_appointments
                          .includes({ contact: :payer }, :professional, :service)
                          .where(starts_at: agenda_date.all_day)
                          .order(:starts_at)
    render json: appointments.map { |appointment| serialize(appointment) }
  end

  # El dia habil (lunes a viernes) mas proximo, estrictamente despues de hoy,
  # que tiene al menos una cita -- salta sabados/domingos aunque tengan citas
  # agendadas. nil si no hay ninguna cita futura en dia habil.
  def next_agenda_date
    next_appointment = Current.account.calendario_appointments
                              .where('starts_at > ?', agenda_zone.now.end_of_day)
                              .order(:starts_at)
                              .find { |appointment| appointment.starts_at.in_time_zone(agenda_zone).on_weekday? }
    render json: { date: next_appointment&.starts_at&.in_time_zone(agenda_zone)&.to_date }
  end

  def create
    appointment = Calendario::AppointmentBookingService.new(
      account: Current.account, params: appointment_params.merge(created_by_id: Current.user.id), force: force_param
    ).perform
    render json: serialize(appointment)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def update
    check_reschedule_warnings if appointment_update_params[:starts_at].present?

    @appointment.update!(appointment_update_params.except(:cancellation_type))
    reactivate_waitlist_if_temporal_cancellation
    render json: serialize(@appointment)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  def agenda_zone
    @agenda_zone ||= ActiveSupport::TimeZone[Current.account.reporting_timezone.presence || 'UTC']
  end

  # params[:date] = "YYYY-MM-DD" interpretado como fecha de calendario en la
  # zona del consultorio (no UTC) -- en blanco = hoy.
  def agenda_date
    return agenda_zone.now if params[:date].blank?

    agenda_zone.parse(params[:date]) || agenda_zone.now
  end

  def fetch_appointment
    @appointment = Current.account.calendario_appointments.find(params[:id])
  end

  def filtered_appointments
    appointments = Current.account.calendario_appointments.includes({ contact: :payer }, :professional, :service)
    appointments = filter_by_starts_at(appointments)
    appointments = filter_by_created_at(appointments)
    appointments = appointments.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    appointments = appointments.where(professional_id: params[:professional_id]) if params[:professional_id].present?
    appointments
  end

  def filter_by_starts_at(appointments)
    return appointments unless params[:since].present? && params[:until].present?

    appointments.where(starts_at: parsed_range)
  end

  def filter_by_created_at(appointments)
    return appointments unless params[:created_since].present? && params[:created_until].present?

    appointments.where(created_at: parsed_created_range)
  end

  def check_reschedule_warnings
    new_ends_at = appointment_update_params[:ends_at].presence || (
      appointment_update_params[:starts_at].to_datetime + (@appointment.ends_at - @appointment.starts_at)
    )
    warnings = Calendario::AppointmentWarningsFinder.new(
      account: Current.account, contact_id: @appointment.contact_id, professional_id: @appointment.professional_id,
      starts_at: appointment_update_params[:starts_at], ends_at: new_ends_at, exclude_id: @appointment.id
    ).find
    raise Calendario::AppointmentWarningsError, warnings if warnings.any? && !force_param
    return unless force_param && warnings.any? { |warning| warning[:type] == 'open_day_missing' }

    Calendario::OpenDayCoverage.new(
      account: Current.account, professional_id: @appointment.professional_id,
      starts_at: appointment_update_params[:starts_at]
    ).ensure!
  end

  def parsed_range
    Time.zone.parse(params[:since])..Time.zone.parse(params[:until])
  end

  # Filtro aparte de parsed_range: busca por cuando se CREO el registro
  # (created_at), no por la fecha agendada (starts_at) -- es lo que necesita
  # la auditoria "que dia se agendaron mas citas" / "quien reservo esto y
  # cuando", independiente de para que dia haya quedado la cita.
  def parsed_created_range
    Time.zone.parse(params[:created_since])..Time.zone.parse(params[:created_until])
  end

  def force_param
    ActiveModel::Type::Boolean.new.cast(params.dig(:appointment, :force))
  end

  def appointment_params
    params.require(:appointment).permit(:professional_id, :service_id, :contact_id, :conversation_id,
                                        :starts_at, :ends_at, :notes)
  end

  def appointment_update_params
    params.require(:appointment).permit(:starts_at, :ends_at, :status, :notes, :cancellation_type)
  end

  # "temporal": el paciente podria necesitar la cita despues (ej. esta
  # enfermo, no sabe cuando puede volver) -- reactiva/crea su entrada de
  # waitlist. "definitiva" (o ausente, compatibilidad con clientes viejos) no
  # toca la waitlist.
  def reactivate_waitlist_if_temporal_cancellation
    return unless @appointment.cancelled?
    return unless appointment_update_params[:cancellation_type] == 'temporal'

    Calendario::WaitlistFulfillmentService.new(appointment: @appointment).reactivate!
  end

  def serialize(appointment)
    {
      id: appointment.id, starts_at: appointment.starts_at, ends_at: appointment.ends_at,
      created_at: appointment.created_at,
      status: appointment.status, notes: appointment.notes,
      professional_id: appointment.professional_id, professional_name: appointment.professional.name,
      service_id: appointment.service_id, service_name: appointment.service.name,
      contact_id: appointment.contact_id, contact_name: appointment.contact.name,
      contact_phone_number: appointment.contact.phone_number, contact_email: appointment.contact.email,
      contact_identifier: appointment.contact.identifier,
      contact_document_type: appointment.contact.document_type,
      contact_secondary_phone_number: appointment.contact.secondary_phone_number,
      conversation_id: appointment.conversation_id,
      reschedules_count: appointment.reschedules_count,
      created_by_name: appointment.created_by&.name,
      payer_id: appointment.contact.payer_id, payer_name: appointment.contact.payer&.name, price: appointment.price
    }
  end

  # Orden mas reciente primero (ver scope default de Calendario::Appointment#audit_logs)
  # -- lo que el personal quiere ver primero es "que paso de ultimas", no el
  # historial completo desde el principio.
  def history_for(appointment)
    appointment.audit_logs.includes(:user).map do |log|
      {
        id: log.id, event_type: log.event_type, created_at: log.created_at,
        user_name: log.user&.name,
        from_starts_at: log.from_starts_at, to_starts_at: log.to_starts_at,
        from_status: log.from_status && Calendario::Appointment.statuses.key(log.from_status),
        to_status: log.to_status && Calendario::Appointment.statuses.key(log.to_status)
      }
    end
  end

  def render_appointment_warnings(error)
    render json: {
      error: I18n.t('calendario.appointments.has_warnings', default: 'This appointment has warnings that need confirmation'),
      warnings: error.warnings.map { |warning| serialize_warning(warning) }
    }, status: :conflict
  end

  def serialize_warning(warning)
    case warning[:type]
    when 'contact_conflict'
      {
        type: 'contact_conflict',
        message: I18n.t('calendario.appointments.contact_conflict',
                        default: '%<contact>s already has an appointment at this time', contact: warning[:conflict].contact.name),
        conflict: serialize(warning[:conflict])
      }
    when 'professional_conflict'
      {
        type: 'professional_conflict',
        message: I18n.t('calendario.appointments.overlapping_appointment',
                        default: 'An appointment already exists for this professional at this time'),
        conflict: serialize(warning[:conflict])
      }
    when 'outside_availability'
      {
        type: 'outside_availability',
        message: I18n.t('calendario.appointments.outside_availability',
                        default: "This time falls outside the professional's configured availability")
      }
    when 'open_day_missing'
      {
        type: 'open_day_missing',
        date: warning[:date],
        time_window: warning[:time_window]
      }
    end
  end

  def check_authorization
    authorize(:'calendario/appointments')
  end
end

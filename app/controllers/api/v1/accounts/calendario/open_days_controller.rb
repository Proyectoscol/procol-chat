class Api::V1::Accounts::Calendario::OpenDaysController < Api::V1::Accounts::BaseController
  wrap_parameters :open_day, include: %i[professional_id date time_window notes force]

  before_action :check_authorization

  def index
    open_days = Current.account.calendario_open_days.includes(:professional)
    open_days = open_days.for_professional(params[:professional_id]) if params[:professional_id].present?
    render json: open_days.order(date: :desc).map { |open_day| serialize(open_day) }
  end

  def create
    open_day = Current.account.calendario_open_days.new(open_day_params.except(:force))
    warning = open_day.duplicate?
    if warning && !force_param
      render json: { error: I18n.t('calendario.open_days.duplicate', default: 'An agenda is already open for this date and window'),
                      warning: 'duplicate' }, status: :conflict
      return
    end

    open_day.opened_by = Current.user
    open_day.save!
    render json: serialize(open_day)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def destroy
    open_day = Current.account.calendario_open_days.find(params[:id])
    open_day.destroy!
    head :no_content
  end

  private

  def force_param
    ActiveModel::Type::Boolean.new.cast(params.dig(:open_day, :force))
  end

  def open_day_params
    params.require(:open_day).permit(:professional_id, :date, :time_window, :notes, :force)
  end

  def serialize(open_day)
    {
      id: open_day.id, professional_id: open_day.professional_id, professional_name: open_day.professional.name,
      date: open_day.date, time_window: open_day.time_window, notes: open_day.notes,
      opened_by_name: open_day.opened_by&.name
    }
  end

  def check_authorization
    authorize(:'calendario/open_days')
  end
end

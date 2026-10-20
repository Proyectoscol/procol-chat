class Api::V2::Accounts::SummaryReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :prepare_builder_params, only: [:agent, :team, :inbox, :label, :channel]

  def agent
    render_report_with(V2::Reports::AgentSummaryBuilder, type: :agent)
  end

  def team
    render_report_with(V2::Reports::TeamSummaryBuilder, type: :team)
  end

  def inbox
    render_report_with(V2::Reports::InboxSummaryBuilder, type: :inbox)
  end

  def label
    render_report_with(V2::Reports::LabelSummaryBuilder)
  end

  def channel
    return render_could_not_create_error(I18n.t('errors.reports.date_range_too_long')) if date_range_too_long?

    render_report_with(V2::Reports::ChannelSummaryBuilder)
  end

  # Cuenta dedicada de Auditoria: no usa reporting_events (ver builder), asi
  # que no comparte prepare_builder_params/render_report_with con el resto.
  def auditoria_advisor
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaAdvisorSummaryBuilder.new(account: Current.account, params: auditoria_params)
    render json: builder.build
  end

  # Click-to-detail del reporte: conversaciones de un asesor en el rango.
  def auditoria_advisor_conversations
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaAdvisorConversationsBuilder.new(
      account: Current.account, params: auditoria_conversations_params
    )
    render json: builder.build
  end

  # Resumen (tabla): cuantas conversaciones distintas tiene cada categoria
  # ahora mismo -- sin since/until, ver comentario en el builder.
  def auditoria_category
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaCategorySummaryBuilder.new(account: Current.account, params: auditoria_category_params)
    render json: builder.build
  end

  # Serie de tiempo (grafica): menciones por dia, filtrable por rango de
  # fechas y por una o varias categorias.
  def auditoria_category_timeseries
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaCategoryMentionsTimeseriesBuilder.new(
      account: Current.account, params: auditoria_category_timeseries_params
    )
    render json: builder.build
  end

  # Click-to-detail del reporte: conversaciones con una categoria puntual.
  def auditoria_category_conversations
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaCategoryConversationsBuilder.new(
      account: Current.account, params: auditoria_category_conversations_params
    )
    render json: builder.build
  end

  # Desglose de una categoria de palabra clave por termino de busqueda.
  def auditoria_category_terms
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaCategoryTermsBuilder.new(account: Current.account, params: auditoria_category_terms_params)
    render json: builder.build
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def prepare_builder_params
    @builder_params = {
      since: permitted_params[:since],
      until: permitted_params[:until],
      business_hours: ActiveModel::Type::Boolean.new.cast(permitted_params[:business_hours])
    }
  end

  def auditoria_params
    params.permit(:since, :until, :inbox_id, :same_day_only)
  end

  def auditoria_conversations_params
    params.permit(:since, :until, :inbox_id, :user_id, :page)
  end

  def auditoria_category_params
    params.permit(:since, :until, :inbox_id, :count_mode)
  end

  def auditoria_category_timeseries_params
    params.permit(:since, :until, :inbox_id, :count_mode, category_ids: [])
  end

  def auditoria_category_conversations_params
    params.permit(:since, :until, :category_id, :inbox_id, :page)
  end

  def auditoria_category_terms_params
    params.permit(:since, :until, :category_id, :inbox_id)
  end

  def render_report_with(builder_class, type: nil)
    builder_params = type.present? ? @builder_params.merge(type: type) : @builder_params
    builder = builder_class.new(account: Current.account, params: builder_params)
    render json: builder.build
  end

  def permitted_params
    params.permit(:since, :until, :business_hours)
  end

  def date_range_too_long?
    return false if permitted_params[:since].blank? || permitted_params[:until].blank?

    since_time = Time.zone.at(permitted_params[:since].to_i)
    until_time = Time.zone.at(permitted_params[:until].to_i)
    (until_time - since_time) > 6.months
  end
end

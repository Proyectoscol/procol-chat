# rubocop:disable Metrics/ClassLength
class Api::V2::Accounts::SummaryReportsController < Api::V1::Accounts::BaseController
  include Api::V2::Accounts::ReportsHelper

  # Limite de filas del CSV de conversaciones (sin paginar) -- una categoria
  # real nunca deberia acercarse a esto; es solo un techo de seguridad, no
  # un limite de negocio esperado.
  CSV_CONVERSATIONS_MAX_ROWS = 10_000

  AUDITORIA_INBOX_SCOPED_ACTIONS = %i[
    auditoria_advisor auditoria_advisor_conversations auditoria_category
    auditoria_category_timeseries auditoria_category_conversations auditoria_category_terms
    auditoria_advisor_daily_rollup auditoria_category_csv auditoria_category_timeseries_csv
    auditoria_category_conversations_csv auditoria_sentiment_timeseries auditoria_sentiment_conversations
  ].freeze

  before_action :check_authorization
  before_action :prepare_builder_params, only: [:agent, :team, :inbox, :label, :channel]
  # Sin filtro de inbox propio hoy (ver prepare_builder_params) -- bloqueadas
  # para un admin restringido en vez de dejarlas sin filtrar (mismo criterio
  # que el resto de reportes no soportados en esta fase).
  before_action -> { render_unauthorized('You are not authorized to do this action') },
                only: [:agent, :team, :inbox, :label, :channel], if: -> { Current.account_user.inbox_restricted? }
  # Los builders de Auditoria ya aceptan inbox_id (filtro existente para
  # cualquier admin) -- para un admin restringido se fuerza al servidor,
  # nunca se confia en lo que mande el cliente.
  before_action -> { params[:inbox_id] = Current.account_user.restricted_inbox_ids },
                only: AUDITORIA_INBOX_SCOPED_ACTIONS, if: -> { Current.account_user.inbox_restricted? }

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

  # Rollup diario por asesor (generado por Auditoria::AdvisorDailyRollupJob,
  # ver config/schedule.yml) -- lee lo ya sintetizado, no corre IA en el
  # request.
  def auditoria_advisor_daily_rollup
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaAdvisorDailyRollupBuilder.new(account: Current.account, params: auditoria_advisor_daily_rollup_params)
    render json: builder.build
  end

  # Tendencia de sentimiento de IA por conversacion (dia/semana/mes),
  # filtrable por asesor, equipo, o bandeja.
  def auditoria_sentiment_timeseries
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaSentimentTimeseriesBuilder.new(
      account: Current.account, params: auditoria_sentiment_timeseries_params
    )
    render json: builder.build
  end

  # Click-to-detail del reporte: conversaciones con un sentimiento puntual.
  def auditoria_sentiment_conversations
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaSentimentConversationsBuilder.new(
      account: Current.account, params: auditoria_sentiment_conversations_params
    )
    render json: builder.build
  end

  def auditoria_category_csv
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    @report_data = auditoria_category_csv_rows
    generate_csv('auditoria_category_report', 'api/v2/accounts/reports/auditoria_category')
  end

  def auditoria_category_timeseries_csv
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    series = V2::Reports::AuditoriaCategoryMentionsTimeseriesBuilder.new(
      account: Current.account, params: auditoria_category_timeseries_params
    ).build[:series]
    @csv_headers = series.pluck(:title)
    @report_data = auditoria_category_timeseries_csv_rows(series)
    generate_csv('auditoria_category_timeseries_report', 'api/v2/accounts/reports/auditoria_category_timeseries')
  end

  # Sin paginar (ver CSV_CONVERSATIONS_MAX_ROWS) -- un export debe traer
  # todo lo que haya, no solo la primera pagina que ve el drawer.
  def auditoria_category_conversations_csv
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('auditoria')

    builder = V2::Reports::AuditoriaCategoryConversationsBuilder.new(
      account: Current.account,
      params: auditoria_category_conversations_params.merge(per_page: CSV_CONVERSATIONS_MAX_ROWS)
    )
    @report_data = auditoria_category_conversations_csv_rows(builder.build[:payload])
    generate_csv('auditoria_category_conversations_report', 'api/v2/accounts/reports/auditoria_category_conversations')
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

  # inbox_id acepta escalar (dropdown normal) O arreglo (admin restringido a
  # varios inboxes, forzado arriba) -- declarar ambas formas a proposito, o
  # permit() descarta en silencio el valor si llega como el otro tipo.
  def auditoria_params
    params.permit(:since, :until, :inbox_id, :same_day_only, inbox_id: [])
  end

  # conversation_ids: alternativa usada por la cita de una etiqueta negativa
  # del resumen diario por asesor (ver AuditoriaAdvisorConversationsBuilder)
  # -- cuando viene, el builder filtra exactamente a esos ids en vez de
  # recalcular por since/until/user_id.
  def auditoria_conversations_params
    params.permit(:since, :until, :inbox_id, :user_id, :page, inbox_id: [], conversation_ids: [])
  end

  def auditoria_category_params
    params.permit(:since, :until, :inbox_id, :count_mode, inbox_id: [])
  end

  def auditoria_category_timeseries_params
    params.permit(:since, :until, :inbox_id, :count_mode, category_ids: [], inbox_id: [])
  end

  # category_ids: alternativa a category_id usada por el clic en un punto
  # de la grafica de tiempo (ver AuditoriaCategoryConversationsBuilder) --
  # filtra por varias categorias HOJA a la vez, sin expansion a descendientes.
  def auditoria_category_conversations_params
    params.permit(:since, :until, :category_id, :inbox_id, :page, :term, inbox_id: [], category_ids: [])
  end

  def auditoria_category_terms_params
    params.permit(:since, :until, :category_id, :inbox_id, :count_mode, inbox_id: [])
  end

  def auditoria_advisor_daily_rollup_params
    params.permit(:since, :until, :inbox_id, :user_id, inbox_id: [], user_id: [])
  end

  def auditoria_sentiment_timeseries_params
    params.permit(:since, :until, :inbox_id, :user_id, :team_id, inbox_id: [])
  end

  def auditoria_sentiment_conversations_params
    params.permit(:since, :until, :inbox_id, :user_id, :team_id, :sentiment, :page, inbox_id: [])
  end

  def auditoria_category_csv_rows
    categories = V2::Reports::AuditoriaCategorySummaryBuilder.new(account: Current.account, params: auditoria_category_params).build[:categories]
    title_by_id = categories.to_h { |category| [category[:id], category[:title]] }
    categories.map { |category| [category[:title], title_by_id[category[:parent_id]], category[:conversations_count]] }
  end

  # Formato ancho: una fila por fecha-bucket, una columna por categoria
  # (ver @csv_headers) -- un bucket sin mencion para una categoria es 0, no
  # una celda vacia, mismo criterio que el relleno de la grafica.
  def auditoria_category_timeseries_csv_rows(series)
    dates = timeseries_csv_dates(series)
    counts = timeseries_csv_counts_by_date_and_category(series)
    dates.map { |date| [date] + series.map { |s| counts[[date, s[:id]]] || 0 } }
  end

  def timeseries_csv_dates(series)
    series.flat_map { |s| s[:points].pluck(:date) }.uniq.sort
  end

  def timeseries_csv_counts_by_date_and_category(series)
    series.each_with_object({}) do |s, acc|
      s[:points].each { |point| acc[[point[:date], s[:id]]] = point[:count] }
    end
  end

  def auditoria_category_conversations_csv_rows(payload)
    payload.map do |record|
      conversation = record[:conversation] || {}
      [
        conversation[:display_id], conversation[:contact_name], conversation[:assignee_name], conversation[:inbox_name],
        conversation[:last_activity_at] ? Time.zone.at(conversation[:last_activity_at]) : nil,
        Array(record[:match_reasons]).join('; ')
      ]
    end
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
# rubocop:enable Metrics/ClassLength

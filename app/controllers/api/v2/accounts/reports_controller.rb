# rubocop:disable Metrics/ClassLength
class Api::V2::Accounts::ReportsController < Api::V1::Accounts::BaseController
  include Api::V2::Accounts::ReportsHelper
  include Api::V2::Accounts::HeatmapHelper

  before_action :check_authorization
  before_action :enforce_inbox_restriction!, if: -> { Current.account_user.inbox_restricted? }

  def index
    builder = V2::Reports::Conversations::ReportBuilder.new(Current.account, report_params)
    data = builder.timeseries
    render json: data
  end

  def summary
    render json: build_summary(:summary)
  end

  def bot_summary
    render json: build_summary(:bot_summary)
  end

  def agents
    @report_data = generate_agents_report
    generate_csv('agents_report', 'api/v2/accounts/reports/agents')
  end

  def inboxes
    @report_data = generate_inboxes_report
    generate_csv('inboxes_report', 'api/v2/accounts/reports/inboxes')
  end

  def labels
    @report_data = generate_labels_report
    generate_csv('labels_report', 'api/v2/accounts/reports/labels')
  end

  def teams
    @report_data = generate_teams_report
    generate_csv('teams_report', 'api/v2/accounts/reports/teams')
  end

  def conversations_summary
    @report_data = generate_conversations_report
    generate_csv('conversations_summary_report', 'api/v2/accounts/reports/conversations_summary')
  end

  def conversation_traffic
    @report_data = generate_conversations_heatmap_report
    timezone_offset = (params[:timezone_offset] || 0).to_f
    @timezone = ActiveSupport::TimeZone[timezone_offset]

    generate_csv('conversation_traffic_reports', 'api/v2/accounts/reports/conversation_traffic')
  end

  def drilldown
    return head :unauthorized unless Current.account_user.administrator?
    return head :unprocessable_entity unless valid_drilldown_params?

    render json: V2::Reports::DrilldownBuilder.new(Current.account, drilldown_params).build
  end

  def conversations
    return head :unprocessable_entity if params[:type].blank?

    render json: conversation_metrics
  end

  def bot_metrics
    bot_metrics = V2::Reports::BotMetricsBuilder.new(Current.account, params).metrics
    render json: bot_metrics
  end

  def inbox_label_matrix
    builder = V2::Reports::InboxLabelMatrixBuilder.new(
      account: Current.account,
      params: inbox_label_matrix_params
    )
    render json: builder.build
  end

  def first_response_time_distribution
    builder = V2::Reports::FirstResponseTimeDistributionBuilder.new(
      account: Current.account,
      params: first_response_time_distribution_params
    )
    render json: builder.build
  end

  OUTGOING_MESSAGES_ALLOWED_GROUP_BY = %w[agent team inbox label].freeze

  def outgoing_messages_count
    return head :unprocessable_entity unless OUTGOING_MESSAGES_ALLOWED_GROUP_BY.include?(params[:group_by])

    builder = V2::Reports::OutgoingMessagesCountBuilder.new(Current.account, outgoing_messages_count_params)
    render json: builder.build
  end

  private

  def generate_csv(filename, template)
    response.headers['Content-Type'] = 'text/csv'
    response.headers['Content-Disposition'] = "attachment; filename=#{filename}.csv"
    render layout: false, template: template, formats: [:csv]
  end

  def check_authorization
    authorize :report, :view?
  end

  # Un admin restringido a inbox(es) solo ve: cuenta (reinterpretada como su
  # unico inbox permitido), inbox (el suyo) y agente (de su equipo) -- el
  # resto de dimensiones/CSVs (label, team, drilldown, bot_metrics, etc.) y
  # cualquier otra accion de este controller quedan bloqueadas en esta fase,
  # nunca visibles sin filtrar. Ver plan: scoping de admins por inbox.
  INBOX_SCOPED_REPORT_ACTIONS = %w[index summary bot_summary].freeze

  def enforce_inbox_restriction!
    return render_unauthorized('You are not authorized to do this action') unless INBOX_SCOPED_REPORT_ACTIONS.include?(action_name)

    case params[:type].to_s
    when 'account' then enforce_account_dimension_scope!
    when 'inbox' then enforce_inbox_dimension_scope!
    when 'agent' then enforce_agent_dimension_scope!
    else render_unauthorized('You are not authorized to do this action')
    end
  end

  # No existe hoy una forma limpia de agregar varios inboxes en un solo
  # "scope" de Reports::DataSource (espera un unico registro con
  # .conversations/.messages) -- con un solo inbox permitido se reescribe
  # transparentemente a la dimension inbox ya soportada; con varios, se
  # bloquea en vez de armar una agregacion fragil sobre codigo compartido.
  def enforce_account_dimension_scope!
    allowed_ids = Current.account_user.restricted_inbox_ids
    return render_unauthorized('You are not authorized to do this action') unless allowed_ids.size == 1

    params[:type] = 'inbox'
    params[:id] = allowed_ids.first
  end

  def enforce_inbox_dimension_scope!
    return if Current.account_user.restricted_inbox_ids.include?(params[:id].to_i)

    render_unauthorized('You are not authorized to do this action')
  end

  def enforce_agent_dimension_scope!
    return if Current.account_user.user_in_scope?(User.find(params[:id]))

    render_unauthorized('You are not authorized to do this action')
  end

  def common_params
    {
      type: params[:type].to_sym,
      id: params[:id],
      group_by: params[:group_by],
      business_hours: ActiveModel::Type::Boolean.new.cast(params[:business_hours])
    }
  end

  def current_summary_params
    common_params.merge({
                          since: range[:current][:since],
                          until: range[:current][:until],
                          timezone_offset: params[:timezone_offset]
                        })
  end

  def previous_summary_params
    common_params.merge({
                          since: range[:previous][:since],
                          until: range[:previous][:until],
                          timezone_offset: params[:timezone_offset]
                        })
  end

  def report_params
    common_params.merge({
                          metric: params[:metric],
                          since: params[:since],
                          until: params[:until],
                          timezone_offset: params[:timezone_offset]
                        })
  end

  def drilldown_params
    permitted_params = params.permit(
      :metric, :id, :since, :until, :group_by, :timezone_offset, :bucket_timestamp, :page, :per_page
    ).to_h.symbolize_keys
    permitted_params.merge(
      type: (params[:type].presence || 'account').to_sym,
      business_hours: ActiveModel::Type::Boolean.new.cast(params[:business_hours])
    )
  end

  def valid_drilldown_params?
    %i[metric bucket_timestamp since until].all? { |param| params[param].present? } &&
      Reports::ReportMetricRegistry.supported?(params[:metric]) &&
      V2::Reports::DrilldownBuilder.supported_dimension_type?(params[:type]) && Reports::DrilldownTimestampValidator.valid?(params)
  end

  def conversation_params
    {
      type: params[:type].to_sym,
      user_id: params[:user_id],
      page: params[:page].presence || 1
    }
  end

  def range
    {
      current: {
        since: params[:since],
        until: params[:until]
      },
      previous: {
        since: (params[:since].to_i - (params[:until].to_i - params[:since].to_i)).to_s,
        until: params[:since]
      }
    }
  end

  def build_summary(method)
    builder = V2::Reports::Conversations::MetricBuilder
    current_summary = builder.new(Current.account, current_summary_params).send(method)
    previous_summary = builder.new(Current.account, previous_summary_params).send(method)
    current_summary.merge(previous: previous_summary)
  end

  def conversation_metrics
    V2::ReportBuilder.new(Current.account, conversation_params).conversation_metrics
  end

  def inbox_label_matrix_params
    {
      since: params[:since],
      until: params[:until],
      inbox_ids: params[:inbox_ids],
      label_ids: params[:label_ids]
    }
  end

  def first_response_time_distribution_params
    {
      since: params[:since],
      until: params[:until]
    }
  end

  def outgoing_messages_count_params
    {
      group_by: params[:group_by],
      since: params[:since],
      until: params[:until]
    }
  end
end
# rubocop:enable Metrics/ClassLength

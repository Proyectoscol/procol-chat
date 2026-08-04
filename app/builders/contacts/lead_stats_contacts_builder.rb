class Contacts::LeadStatsContactsBuilder
  include TimezoneHelper

  RESULTS_PER_PAGE = 15

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def contacts
    @contacts ||= apply_hour_of_day_filter(filter.relation)
                  .order(created_at: :desc)
                  .includes(avatar_attachment: [:blob])
                  .page(current_page)
                  .per(RESULTS_PER_PAGE)
  end

  def current_page
    @current_page ||= (params[:page] || 1).to_i
  end

  def total_count
    contacts.total_count
  end

  def labels_by_contact_id
    @labels_by_contact_id ||= Contacts::ConversationLabelsPreloader.call(contacts.map(&:id))
  end

  private

  attr_reader :account, :params

  def filter
    @filter ||= Contacts::LeadStatsFilter.new(account: account, params: params)
  end

  # `hour_of_day` narrows the contacts list to a specific local hour across the
  # whole date range (from clicking the hourly chart) — kept out of
  # Contacts::LeadStatsFilter on purpose, so it only affects this listing and
  # not the shared aggregates/breakdowns, same as the daily-chart drill-down.
  def apply_hour_of_day_filter(relation)
    return relation if params[:hour_of_day].blank?

    relation.where(
      ActiveRecord::Base.sanitize_sql_array(
        ["EXTRACT(HOUR FROM contacts.created_at AT TIME ZONE 'UTC' AT TIME ZONE ?) = ?", timezone_name, params[:hour_of_day].to_i]
      )
    )
  end

  def timezone_name
    zone = timezone_name_from_offset(params[:timezone_offset])
    ActiveSupport::TimeZone[zone]&.tzinfo&.name || 'UTC'
  end
end

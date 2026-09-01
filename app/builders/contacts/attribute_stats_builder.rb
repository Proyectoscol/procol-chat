class Contacts::AttributeStatsBuilder
  include DateRangeHelper
  include TimezoneHelper

  MAX_VALUES_PER_KEY = 12
  BLANK_LABEL = Contacts::LeadStatsFilter::BLANK_LABEL

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    {
      total_count: filter.relation.count,
      keys: filter.available_keys,
      breakdowns: filter.available_keys.index_with { |key| breakdown_for(key) },
      custom_keys: filter.available_custom_attribute_keys,
      custom_breakdowns: filter.available_custom_attribute_keys.index_with { |key| custom_breakdown_for(key) },
      label_counts: filter.label_counts,
      daily_series: daily_series,
      hourly_series: hourly_series
    }
  end

  private

  attr_reader :account, :params

  def filter
    @filter ||= Contacts::LeadStatsFilter.new(account: account, params: params)
  end

  def breakdown_for(key)
    filter.relation
          .group(Arel.sql(ActiveRecord::Base.sanitize_sql_array(["NULLIF(contacts.additional_attributes ->> ?, '')", key])))
          .count
          .transform_keys { |v| v || BLANK_LABEL }
          .sort_by { |_, count| -count }
          .first(MAX_VALUES_PER_KEY)
          .to_h
  end

  def custom_breakdown_for(key)
    filter.relation
          .group(Arel.sql(ActiveRecord::Base.sanitize_sql_array(["NULLIF(contacts.custom_attributes ->> ?, '')", key])))
          .count
          .transform_keys { |v| v || BLANK_LABEL }
          .sort_by { |_, count| -count }
          .first(MAX_VALUES_PER_KEY)
          .to_h
  end

  def daily_series
    totals = group_by_day(filter.relation_without_label_filter)
    label_series = filter.label_titles.index_with { |title| group_by_day(filter.relation_for_single_label(title)) }

    totals.keys.sort.map do |bucket|
      {
        date: bucket.to_date.iso8601,
        timestamp: bucket.to_time.to_i,
        total: totals[bucket] || 0,
        labels: label_series.transform_values { |series| series[bucket] || 0 }
      }
    end
  end

  def hourly_series
    filter.relation
          .group_by_hour_of_day(:created_at, default_value: 0, time_zone: timezone)
          .count
          .sort
          .map { |hour, total| { hour: hour, total: total } }
  end

  def group_by_day(relation)
    relation.group_by_period(:day, :created_at, default_value: 0, range: series_range, time_zone: timezone).count
  end

  def series_range
    range.presence || (30.days.ago..Time.current)
  end

  # Prefer the browser's own timezone (sent as `timezone_offset`, same convention
  # used by the Reports module) over the account's `reporting_timezone` setting,
  # so the daily/hourly buckets always match how the viewer perceives "today" —
  # not a possibly-unset or stale account-level setting.
  def timezone
    return timezone_name_from_offset(params[:timezone_offset]) if params[:timezone_offset].present?

    account.reporting_timezone.presence || 'UTC'
  end
end

class Contacts::AttributeStatsBuilder
  include DateRangeHelper

  DENYLIST_KEYS = %w[social_profiles avatar_url_hash last_avatar_sync_at organization_id lead_timestamp].freeze
  MAX_VALUES_PER_KEY = 12
  BLANK_LABEL = 'N/A'.freeze

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    {
      total_count: base_relation.count,
      keys: available_keys,
      breakdowns: available_keys.index_with { |key| breakdown_for(key) }
    }
  end

  private

  attr_reader :account, :params

  def base_relation
    @base_relation ||= begin
      relation = account.contacts
      relation = relation.where(created_at: range) if range.present?
      relation = relation.where(id: ContactInbox.where(inbox_id: params[:inbox_id]).select(:contact_id)) if params[:inbox_id].present?
      active_filters.each { |key, value| relation = relation.where(attribute_equals_sql(key, value)) }
      relation
    end
  end

  def attribute_equals_sql(key, value)
    if value == BLANK_LABEL
      ActiveRecord::Base.sanitize_sql_array(
        ['(contacts.additional_attributes ->> ? IS NULL OR contacts.additional_attributes ->> ? = ?)', key, key, '']
      )
    else
      ActiveRecord::Base.sanitize_sql_array(['contacts.additional_attributes ->> ? = ?', key, value])
    end
  end

  def active_filters
    raw = params[:filters].is_a?(ActionController::Parameters) ? params[:filters].to_unsafe_h : (params[:filters] || {})
    raw.slice(*available_keys)
  end

  def discovered_keys
    @discovered_keys ||= ActiveRecord::Base.connection.select_values(
      ActiveRecord::Base.sanitize_sql_array(
        ['SELECT DISTINCT jsonb_object_keys(additional_attributes) FROM contacts WHERE account_id = ?', account.id]
      )
    )
  end

  def available_keys
    @available_keys ||= discovered_keys - DENYLIST_KEYS
  end

  def breakdown_for(key)
    base_relation
      .group(Arel.sql(ActiveRecord::Base.sanitize_sql_array(["NULLIF(contacts.additional_attributes ->> ?, '')", key])))
      .count
      .transform_keys { |v| v || BLANK_LABEL }
      .sort_by { |_, count| -count }
      .first(MAX_VALUES_PER_KEY)
      .to_h
  end
end

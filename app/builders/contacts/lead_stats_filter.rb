class Contacts::LeadStatsFilter
  include DateRangeHelper

  DENYLIST_KEYS = %w[social_profiles avatar_url_hash last_avatar_sync_at organization_id lead_timestamp].freeze
  BLANK_LABEL = 'N/A'.freeze

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  # Fully filtered relation: date range + inbox + additional_attributes filters + label_titles (OR'd).
  # Used for total_count, breakdowns, the contacts list, and export.
  def relation
    @relation ||= apply_label_filter(base_relation, label_titles)
  end

  # Same as `relation` but without narrowing by label_titles — used as the baseline
  # ("total ingress that day") for the daily trend chart, so tag overlay lines can be
  # compared against the full volume instead of only the tag-narrowed subset.
  def relation_without_label_filter
    base_relation
  end

  # `base_relation` further narrowed to a single label (independent of `label_titles`) —
  # used to compute one overlay series per selected tag on the daily trend chart.
  def relation_for_single_label(title)
    apply_label_filter(base_relation, [title])
  end

  def label_titles
    @label_titles ||= Array(params[:label_titles]).map(&:to_s).reject(&:blank?)
  end

  def available_keys
    @available_keys ||= discovered_keys - DENYLIST_KEYS
  end

  # All contact-level custom attributes defined on the account, regardless of
  # whether a given contact has a value for them — lets the export show one
  # column per definition, blank where the contact has no value.
  def available_custom_attribute_keys
    @available_custom_attribute_keys ||= account.custom_attribute_definitions.contact_attribute.pluck(:attribute_key)
  end

  private

  attr_reader :account, :params

  def base_relation
    @base_relation ||= begin
      scoped = account.contacts.where(internal: false)
      scoped = scoped.where(created_at: range) if range.present?
      scoped = scoped.where(id: ContactInbox.where(inbox_id: params[:inbox_id]).select(:contact_id)) if params[:inbox_id].present?
      active_filters.each { |key, value| scoped = scoped.where(attribute_equals_sql(key, value)) }
      scoped
    end
  end

  def apply_label_filter(scoped, titles)
    return scoped if titles.blank?

    scoped.where(id: Conversation.tagged_with(titles, any: true).reselect(:contact_id))
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
        ['SELECT DISTINCT jsonb_object_keys(additional_attributes) FROM contacts WHERE account_id = ? AND internal = false', account.id]
      )
    )
  end
end

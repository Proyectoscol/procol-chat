class Account::LeadStatsExportJob < ApplicationJob
  queue_as :low

  BASE_COLUMNS = %w[id name phone_number email country_code location created_at last_activity_at].freeze
  LABELS_COLUMN = 'labels'.freeze
  LABELS_DELIMITER = ','.freeze
  CUSTOM_ATTRIBUTE_PREFIX = 'custom_'.freeze
  TIMESTAMP_COLUMNS = %w[created_at last_activity_at].freeze

  def perform(account_id, user_id, params)
    @account = Account.find(account_id)
    @account_user = @account.users.find(user_id)
    @params = params.with_indifferent_access

    generate_csv
    notify_export_ready
  end

  private

  def filter
    @filter ||= Contacts::LeadStatsFilter.new(account: @account, params: @params)
  end

  def custom_attribute_headers
    filter.available_custom_attribute_keys.map { |key| "#{CUSTOM_ATTRIBUTE_PREFIX}#{key}" }
  end

  def headers
    @headers ||= BASE_COLUMNS + [LABELS_COLUMN] + filter.available_keys + custom_attribute_headers
  end

  def generate_csv
    contacts_to_export = filter.relation.order(created_at: :desc).to_a
    @labels_by_contact_id = Contacts::ConversationLabelsPreloader.call(contacts_to_export.map(&:id))

    csv_data = CSV.generate do |csv|
      csv << headers
      contacts_to_export.each { |contact| csv << headers.map { |header| value_for(contact, header) } }
    end

    attach_export_file(csv_data)
  end

  def value_for(contact, header)
    return @labels_by_contact_id.fetch(contact.id, []).join(LABELS_DELIMITER) if header == LABELS_COLUMN
    return contact.send(header)&.iso8601 if TIMESTAMP_COLUMNS.include?(header)
    return contact.custom_attributes[header.delete_prefix(CUSTOM_ATTRIBUTE_PREFIX)] if header.start_with?(CUSTOM_ATTRIBUTE_PREFIX)
    return contact.additional_attributes[header] unless BASE_COLUMNS.include?(header)

    contact.send(header)
  end

  def attach_export_file(csv_data)
    return if csv_data.blank?

    # Prepend UTF-8 BOM so that spreadsheet applications (e.g. Excel)
    # correctly recognise the file encoding for non-ASCII characters.
    bom = "\xEF\xBB\xBF"

    @account.lead_stats_export.attach(
      io: StringIO.new("#{bom}#{csv_data}"),
      filename: "#{@account.name}_#{@account.id}_lead_stats.csv",
      content_type: 'text/csv'
    )
  end

  # No email involved: the file is attached above, and the browser is told to
  # download it the moment it's ready via ActionCable (same pattern as
  # Account::BrandingEnrichmentJob's 'account.enrichment_completed' broadcast).
  def notify_export_ready
    return unless @account.lead_stats_export.attached?

    file_url = Rails.application.routes.url_helpers.rails_blob_url(@account.lead_stats_export)
    data = { account_id: @account.id, download_url: file_url }
    ActionCableBroadcastJob.perform_later([@account_user.pubsub_token], 'lead_stats_export.completed', data)
  end
end

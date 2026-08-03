class Account::LeadStatsExportJob < ApplicationJob
  queue_as :low

  BASE_COLUMNS = %w[id name email phone_number created_at].freeze
  LABELS_COLUMN = 'labels'.freeze
  LABELS_DELIMITER = ','.freeze

  def perform(account_id, user_id, params)
    @account = Account.find(account_id)
    @account_user = @account.users.find(user_id)
    @params = params.with_indifferent_access

    generate_csv
    send_mail
  end

  private

  def filter
    @filter ||= Contacts::LeadStatsFilter.new(account: @account, params: @params)
  end

  def headers
    @headers ||= BASE_COLUMNS + filter.available_keys + [LABELS_COLUMN]
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
    return contact.created_at.iso8601 if header == 'created_at'
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

  def send_mail
    file_url = Rails.application.routes.url_helpers.rails_blob_url(@account.lead_stats_export)
    mailer = AdministratorNotifications::AccountNotificationMailer.with(account: @account)
    mailer.contact_export_complete(file_url, @account_user.email)&.deliver_later
  end
end

class Api::V1::Accounts::Contacts::LeadStatsController < Api::V1::Accounts::BaseController
  def contacts
    authorize(Contact, :lead_stats_contacts?)

    builder = Contacts::LeadStatsContactsBuilder.new(account: Current.account, params: params)
    @contacts = builder.contacts
    @contacts_count = builder.total_count
    @contact_labels_by_id = builder.labels_by_contact_id
    @current_page = builder.current_page
  end

  def export
    authorize(Contact, :lead_stats_export?)

    ::Account::LeadStatsExportJob.perform_later(Current.account.id, Current.user.id, params.permit!.to_h)
    head :ok
  end
end

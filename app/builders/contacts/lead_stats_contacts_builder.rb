class Contacts::LeadStatsContactsBuilder
  RESULTS_PER_PAGE = 15

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def contacts
    @contacts ||= filter.relation
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
end

require 'rails_helper'

RSpec.describe Auditoria::AdvisorDailySummary do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  it 'is valid with the required associations and a unique summary_date per account/user' do
    summary = described_class.new(account: account, user: user, summary_date: Date.yesterday)

    expect(summary).to be_valid
  end

  it 'does not allow two summaries for the same account/user/summary_date' do
    described_class.create!(account: account, user: user, summary_date: Date.yesterday)
    duplicate = described_class.new(account: account, user: user, summary_date: Date.yesterday)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:summary_date]).to be_present
  end

  it 'allows the same summary_date for a different user in the same account' do
    described_class.create!(account: account, user: user, summary_date: Date.yesterday)
    other_user = create(:user, account: account)
    other_summary = described_class.new(account: account, user: other_user, summary_date: Date.yesterday)

    expect(other_summary).to be_valid
  end
end

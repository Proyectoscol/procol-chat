require 'rails_helper'

RSpec.describe Auditoria::AiUsagePolicy, type: :policy do
  subject(:policy) { described_class }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:restricted_administrator) { create(:user, :administrator, account: account) }
  let(:agent) { create(:user, account: account) }
  let(:administrator_context) { { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) } }
  let(:restricted_administrator_context) do
    account_user = restricted_administrator.account_users.find_by(account: account)
    account_user.update!(restricted_inbox_ids: [inbox.id])
    { user: restricted_administrator, account: account, account_user: account_user }
  end
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.find_by(account: account) } }

  permissions :summary?, :index? do
    it 'allows administrators and agents' do
      expect(policy).to permit(administrator_context, :auditoria_ai_usage)
      expect(policy).to permit(agent_context, :auditoria_ai_usage)
    end
  end

  permissions :update_settings? do
    it 'allows an unrestricted administrator' do
      expect(policy).to permit(administrator_context, :auditoria_ai_usage)
    end

    it 'denies an administrator restricted to specific inboxes (account-wide setting)' do
      expect(policy).not_to permit(restricted_administrator_context, :auditoria_ai_usage)
    end

    it 'denies a regular agent' do
      expect(policy).not_to permit(agent_context, :auditoria_ai_usage)
    end
  end
end

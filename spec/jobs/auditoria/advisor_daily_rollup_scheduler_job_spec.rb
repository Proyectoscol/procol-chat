require 'rails_helper'

RSpec.describe Auditoria::AdvisorDailyRollupSchedulerJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:summary_date) { Date.yesterday }

  def message_from(advisor, conversation: nil)
    conversation ||= create(:conversation, account: account, inbox: inbox, created_at: summary_date.noon)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: 'outgoing', created_at: summary_date.noon,
                     content_attributes: { 'auditoria_source_user_id' => advisor.id })
    conversation
  end

  describe '.agent_ids_with_activity' do
    it 'returns the distinct advisors with messages on that day' do
      advisor_one = create(:user, account: account)
      advisor_two = create(:user, account: account)
      message_from(advisor_one)
      message_from(advisor_two)

      expect(described_class.agent_ids_with_activity(account, summary_date)).to contain_exactly(advisor_one.id, advisor_two.id)
    end

    it 'excludes conversations tagged as having multiple advisors' do
      advisor = create(:user, account: account)
      conversation = message_from(advisor)
      conversation.update_labels(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE)

      expect(described_class.agent_ids_with_activity(account, summary_date)).to be_empty
    end

    it 'ignores messages outside the requested day' do
      advisor = create(:user, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, created_at: summary_date - 2.days)
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: 'outgoing', created_at: summary_date - 2.days,
                       content_attributes: { 'auditoria_source_user_id' => advisor.id })

      expect(described_class.agent_ids_with_activity(account, summary_date)).to be_empty
    end
  end

  describe '#perform' do
    before { account.enable_features!('auditoria') }

    it 'only schedules rollups for accounts with the auditoria feature enabled' do
      disabled_account = create(:account)
      allow(Account).to receive(:all).and_return(Account.where(id: [account.id, disabled_account.id]))
      allow(described_class).to receive(:agent_ids_with_activity).and_return([])

      described_class.perform_now(summary_date: summary_date, track_progress: false)

      expect(described_class).to have_received(:agent_ids_with_activity).with(account, summary_date)
      expect(described_class).not_to have_received(:agent_ids_with_activity).with(disabled_account, summary_date)
    end

    it 'enqueues one Auditoria::AdvisorDailyRollupJob per advisor with activity' do
      advisor = create(:user, account: account)
      message_from(advisor)

      expect { described_class.perform_now(summary_date: summary_date, account_id: account.id, track_progress: false) }
        .to have_enqueued_job(Auditoria::AdvisorDailyRollupJob)
        .with(account.id, advisor.id, summary_date, triggered_by: :batch, pipeline_run_kind: nil)
    end
  end
end

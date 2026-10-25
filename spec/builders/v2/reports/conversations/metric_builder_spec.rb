require 'rails_helper'

RSpec.describe V2::Reports::Conversations::MetricBuilder, type: :model do
  subject { described_class.new(account, params) }

  let(:account) { create(:account) }
  let(:params) { { since: '2023-01-01', until: '2024-01-01' } }
  let(:builder_instance) { instance_double(V2::Reports::Timeseries::ReportBuilder, aggregate_value: 42) }

  before do
    allow(V2::Reports::Timeseries::ReportBuilder).to receive(:new).and_return(builder_instance)
  end

  describe '#summary' do
    it 'returns the correct summary values' do
      summary = subject.summary
      expect(summary).to eq(
        {
          conversations_count: 42,
          incoming_messages_count: 42,
          outgoing_messages_count: 42,
          avg_first_response_time: 42,
          avg_resolution_time: 42,
          resolutions_count: 42,
          reply_time: 42
        }
      )
    end

    it 'creates builders with proper params' do
      subject.summary
      expect(V2::Reports::Timeseries::ReportBuilder).to have_received(:new).with(account, params.merge(metric: 'conversations_count'))
      expect(V2::Reports::Timeseries::ReportBuilder).to have_received(:new).with(account, params.merge(metric: 'avg_first_response_time'))
    end
  end

  describe '#summary with the Auditoria fallback' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:nil_builder) { instance_double(V2::Reports::Timeseries::ReportBuilder, aggregate_value: nil) }

    before do
      allow(V2::Reports::Timeseries::ReportBuilder).to receive(:new).and_return(nil_builder)
      account.enable_features!('auditoria')
    end

    def seed_response_gap(inbox, seconds:)
      contact = create(:contact, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      incoming_at = 1.hour.ago
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: incoming_at)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: incoming_at + seconds)
    end

    context 'when type is account (or absent)' do
      let(:params) { { since: 1.day.ago.to_i.to_s, until: Time.current.to_i.to_s } }

      it 'falls back to the account-wide Auditoria response-time calculation' do
        seed_response_gap(inbox, seconds: 45)

        expect(described_class.new(account, params).summary[:avg_first_response_time]).to eq(45)
      end
    end

    context 'when type is inbox with a specific id' do
      let(:other_inbox) { create(:inbox, account: account) }
      let(:params) { { since: 1.day.ago.to_i.to_s, until: Time.current.to_i.to_s, type: :inbox, id: inbox.id.to_s } }

      it 'only considers that inbox, never the whole account' do
        seed_response_gap(inbox, seconds: 45)
        seed_response_gap(other_inbox, seconds: 9999)

        expect(described_class.new(account, params).summary[:avg_first_response_time]).to eq(45)
      end

      it 'returns nil when that specific inbox has no data, even if other inboxes do' do
        seed_response_gap(other_inbox, seconds: 9999)

        expect(described_class.new(account, params).summary[:avg_first_response_time]).to be_nil
      end
    end
  end

  describe '#bot_summary' do
    it 'returns a detailed summary of bot-specific conversation metrics' do
      bot_summary = subject.bot_summary
      expect(bot_summary).to eq(
        {
          bot_resolutions_count: 42,
          bot_handoffs_count: 42
        }
      )
    end
  end
end

require 'rails_helper'

RSpec.describe V2::Reports::AuditoriaAdvisorSummaryBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:advisor) { create(:user, account: account, role: :agent) }
  let(:since) { 1.day.ago.to_i.to_s }
  let(:until_) { Time.current.to_i.to_s }
  let(:builder) { described_class.new(account: account, params: { since: since, until: until_ }) }

  def row_for(advisor)
    builder.build[:advisors].find { |r| r[:id] == advisor.id }
  end

  describe '#build' do
    it 'measures the response gap even when an activity message (e.g. assignment) sits between the incoming and the reply' do
      conversation = create(:conversation, account: account, inbox: inbox)
      incoming_at = 1.hour.ago
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: incoming_at)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity,
                       content: 'Conversation assigned', created_at: incoming_at + 5)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: incoming_at + 60,
                       content_attributes: { 'auditoria_source_user_id' => advisor.id })

      row = row_for(advisor)

      expect(row[:avg_response_time_seconds]).to eq(60)
      expect(row[:response_breakdown]).to eq([{ order: 1, avg_response_time_seconds: 60, count: 1 }])
    end

    it 'still counts the conversation itself even when the response gap is lost' do
      conversation = create(:conversation, account: account, inbox: inbox)
      incoming_at = 1.hour.ago
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: incoming_at)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: incoming_at + 60,
                       content_attributes: { 'auditoria_source_user_id' => advisor.id })

      expect(row_for(advisor)[:conversations_count]).to eq(1)
    end
  end
end

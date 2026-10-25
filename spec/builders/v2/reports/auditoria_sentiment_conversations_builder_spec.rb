require 'rails_helper'

RSpec.describe V2::Reports::AuditoriaSentimentConversationsBuilder do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let(:since) { 10.days.ago.beginning_of_day.to_i }
  let(:until_) { Time.current.end_of_day.to_i }
  let(:params) { { since: since, until: until_ } }
  let(:builder) { described_class.new(account: account, params: params) }

  # rubocop:disable Metrics/ParameterLists
  def analysis_for(sentiment:, created_at: 2.days.ago.noon, labels: [], source_user: nil, conversation_inbox: inbox, sentiment_reason: nil)
    # rubocop:enable Metrics/ParameterLists
    conversation = create(:conversation, account: account, inbox: conversation_inbox, created_at: created_at)
    conversation.update_labels(*labels) if labels.any?
    if source_user
      create(:message, account: account, inbox: conversation_inbox, conversation: conversation,
                       message_type: 'outgoing', content_attributes: { 'auditoria_source_user_id' => source_user.id })
    end
    create(:auditoria_conversation_analysis, account: account, conversation: conversation, sentiment: sentiment, sentiment_reason: sentiment_reason)
    conversation
  end

  describe '#build' do
    it 'returns conversations with any of the 3 sentiments when none is specified' do
      analysis_for(sentiment: 'positive')
      analysis_for(sentiment: 'neutral')
      analysis_for(sentiment: 'negative')

      expect(builder.build[:meta][:total_count]).to eq(3)
    end

    it 'includes the sentiment of each conversation in the payload' do
      conversation = analysis_for(sentiment: 'negative')

      row = builder.build[:payload].find { |r| r[:conversation][:id] == conversation.id }
      expect(row[:sentiment]).to eq('negative')
    end

    it 'includes the sentiment reason of each conversation in the payload' do
      conversation = analysis_for(sentiment: 'negative', sentiment_reason: 'El cliente se quejo del tiempo de espera')

      row = builder.build[:payload].find { |r| r[:conversation][:id] == conversation.id }
      expect(row[:sentiment_reason]).to eq('El cliente se quejo del tiempo de espera')
    end

    context 'with a sentiment filter' do
      let(:params) { { since: since, until: until_, sentiment: 'positive' } }

      it 'only returns conversations with that sentiment' do
        analysis_for(sentiment: 'positive')
        analysis_for(sentiment: 'negative')

        expect(builder.build[:meta][:total_count]).to eq(1)
      end
    end

    it 'excludes conversations tagged as having multiple advisors' do
      analysis_for(sentiment: 'positive', labels: [Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE])

      expect(builder.build[:meta][:total_count]).to eq(0)
    end

    it 'only includes conversations within the requested date range' do
      analysis_for(sentiment: 'positive', created_at: 20.days.ago.noon)

      expect(builder.build[:meta][:total_count]).to eq(0)
    end

    context 'with inbox_id filter' do
      let!(:other_inbox) { create(:inbox, account: account, name: 'Other inbox') }
      let(:params) { { since: since, until: until_, inbox_id: inbox.id } }

      it 'only includes conversations from the given inbox' do
        analysis_for(sentiment: 'positive', conversation_inbox: inbox)
        analysis_for(sentiment: 'positive', conversation_inbox: other_inbox)

        expect(builder.build[:meta][:total_count]).to eq(1)
      end
    end

    context 'with user_id filter' do
      let!(:advisor) { create(:user, account: account) }
      let!(:other_advisor) { create(:user, account: account) }
      let(:params) { { since: since, until: until_, user_id: advisor.id } }

      it 'only includes conversations attributed to that advisor' do
        analysis_for(sentiment: 'positive', source_user: advisor)
        analysis_for(sentiment: 'positive', source_user: other_advisor)

        expect(builder.build[:meta][:total_count]).to eq(1)
      end
    end

    context 'with a page beyond the first' do
      let(:params) { { since: since, until: until_, page: 2 } }

      it 'paginates with DEFAULT_PER_PAGE results per page' do
        create_list(:conversation, 30, account: account, inbox: inbox, created_at: 2.days.ago.noon).each do |conversation|
          create(:auditoria_conversation_analysis, account: account, conversation: conversation, sentiment: 'positive')
        end

        result = builder.build
        expect(result[:meta][:total_count]).to eq(30)
        expect(result[:meta][:current_page]).to eq(2)
        expect(result[:payload].size).to eq(5)
      end
    end
  end
end

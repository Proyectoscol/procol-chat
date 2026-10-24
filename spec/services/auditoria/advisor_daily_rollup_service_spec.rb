require 'rails_helper'

RSpec.describe Auditoria::AdvisorDailyRollupService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:advisor) { create(:user, account: account) }
  let(:summary_date) { Date.yesterday }
  let(:service) { described_class.new(account: account, user: advisor, summary_date: summary_date) }

  let(:ai_response) do
    {
      message: {
        summary: 'Buen dia en general.',
        tone_overview: 'Positivo',
        recommendation: 'Seguir asi',
        short_feedback: 'Buen manejo de objeciones',
        short_feedback_reason: 'Conversacion 1',
        feedback_tags_positive: ['buena empatia'],
        feedback_tags_negative: []
      },
      model: 'gpt-4', usage: { 'prompt_tokens' => 10, 'completion_tokens' => 20 }
    }
  end

  def conversation_attended_by(advisor, created_at: summary_date.noon)
    conversation = create(:conversation, account: account, inbox: inbox, created_at: created_at)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: 'outgoing', created_at: created_at,
                     content_attributes: { 'auditoria_source_user_id' => advisor.id })
    conversation
  end

  before do
    allow(Auditoria::AiUsageLogger).to receive(:within_limit?).and_return(true)
    allow(Auditoria::AiUsageLogger).to receive(:log!)
    allow(service).to receive(:make_api_call).and_return(ai_response)
    # Enterprise::Captain::BaseTaskService#perform (prepended) short-circuits before
    # reaching AdvisorDailyRollupService#perform if captain_tasks is disabled.
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
  end

  describe '#perform' do
    it 'skips when the advisor had no conversations that day' do
      result = service.perform

      expect(result).to eq({ message: nil, skipped: true })
      expect(service).not_to have_received(:make_api_call)
    end

    it 'returns a spend limit error without calling the AI when the account is over its limit' do
      conversation_attended_by(advisor)
      allow(Auditoria::AiUsageLogger).to receive(:within_limit?).and_return(false)

      result = service.perform

      expect(result[:error]).to eq(I18n.t('auditoria.ai_spend_limit_reached'))
      expect(service).not_to have_received(:make_api_call)
    end

    it 'excludes conversations tagged as having multiple advisors' do
      conversation = conversation_attended_by(advisor)
      conversation.update_labels(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE)

      result = service.perform

      expect(result).to eq({ message: nil, skipped: true })
    end

    context 'when every attended conversation already has an analysis' do
      it 'persists conversations_count equal to the number of conversations attended that day' do
        conversations = create_list(:conversation, 2, account: account, inbox: inbox, created_at: summary_date.noon)
        conversations.each do |conversation|
          create(:message, account: account, inbox: inbox, conversation: conversation,
                           message_type: 'outgoing', created_at: summary_date.noon,
                           content_attributes: { 'auditoria_source_user_id' => advisor.id })
          create(:auditoria_conversation_analysis, account: account, conversation: conversation)
        end

        service.perform

        summary = Auditoria::AdvisorDailySummary.find_by(account: account, user: advisor, summary_date: summary_date)
        expect(summary.conversations_count).to eq(2)
      end
    end

    context 'when stage 1 (per-conversation analysis) has not finished for every attended conversation' do
      it 'persists conversations_count from the analyses actually fed to the AI, not from every conversation attended' do
        analyzed_conversation = conversation_attended_by(advisor)
        create(:auditoria_conversation_analysis, account: account, conversation: analyzed_conversation)
        conversation_attended_by(advisor) # no Auditoria::ConversationAnalysis yet -- stage 1 still running

        service.perform

        summary = Auditoria::AdvisorDailySummary.find_by(account: account, user: advisor, summary_date: summary_date)
        expect(summary.conversations_count).to eq(1)
      end
    end

    it 'translates feedback_tags_negative conversation_numbers to real conversation_ids' do
      conversation = conversation_attended_by(advisor)
      create(:auditoria_conversation_analysis, account: account, conversation: conversation)
      allow(service).to receive(:make_api_call).and_return(
        ai_response.deep_merge(message: { feedback_tags_negative: [{ tag: 'manejo de objeciones', reason: 'x', conversation_numbers: [1] }] })
      )

      service.perform

      summary = Auditoria::AdvisorDailySummary.find_by(account: account, user: advisor, summary_date: summary_date)
      expect(summary.feedback_tags_negative).to eq(['manejo de objeciones'])
      expect(summary.feedback_tags_negative_detail.first['conversation_ids']).to eq([conversation.id])
    end
  end
end

require 'rails_helper'

RSpec.describe Auditoria::ConversationAnalyzerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:service) { described_class.new(account: account, conversation_display_id: conversation.display_id) }

  let(:ai_response) do
    {
      message: {
        field_1: 'Resumen', field_2: 'Tono', field_3: 'Recomendacion', field_4: 'Objeciones', field_5: 'Opinion',
        sentiment: 'neutral'
      },
      model: 'gpt-4', usage: { 'prompt_tokens' => 10, 'completion_tokens' => 20 }
    }
  end

  before do
    allow(Auditoria::AiUsageLogger).to receive(:within_limit?).and_return(true)
    allow(Auditoria::AiUsageLogger).to receive(:log!)
    allow(service).to receive(:make_api_call).and_return(ai_response)
    # Enterprise::Captain::BaseTaskService#perform (prepended) short-circuita antes
    # de llegar a ConversationAnalyzerService#perform si captain_tasks esta deshabilitado.
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
  end

  describe '#perform' do
    context 'when there are no active AI field configs' do
      it 'returns an error without calling the AI' do
        result = service.perform

        expect(result[:error]).to eq(I18n.t('auditoria.no_active_fields_to_analyze'))
        expect(service).not_to have_received(:make_api_call)
      end
    end

    context 'with active field configs' do
      before { account.auditoria_ai_field_configs.create!(field_order: 1, title: 'Resumen') }

      it 'returns an error without calling the AI when the conversation has no incoming/outgoing messages' do
        result = service.perform

        expect(result[:error]).to eq(I18n.t('auditoria.no_messages_to_analyze'))
        expect(service).not_to have_received(:make_api_call)
      end

      it 'persists the analysis when the conversation has messages' do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', content: 'Hola')

        service.perform

        analysis = Auditoria::ConversationAnalysis.find_by(conversation: conversation)
        expect(analysis.results).to include('field_1' => 'Resumen')
        expect(analysis.sentiment).to eq('neutral')
      end

      it 'returns a spend limit error without calling the AI when the account is over its limit' do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', content: 'Hola')
        allow(Auditoria::AiUsageLogger).to receive(:within_limit?).and_return(false)

        result = service.perform

        expect(result[:error]).to eq(I18n.t('auditoria.ai_spend_limit_reached'))
        expect(service).not_to have_received(:make_api_call)
      end
    end
  end
end

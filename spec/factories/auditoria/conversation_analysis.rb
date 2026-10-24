FactoryBot.define do
  factory :auditoria_conversation_analysis, class: 'Auditoria::ConversationAnalysis' do
    association :account
    association :conversation
    sentiment { 'neutral' }
    analyzed_at { Time.current }
  end
end

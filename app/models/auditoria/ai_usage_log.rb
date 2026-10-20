# == Schema Information
#
# Table name: auditoria_ai_usage_logs
#
#  id                :bigint           not null, primary key
#  completion_tokens :integer
#  cost_usd          :decimal(10, 6)
#  feature           :integer          not null
#  model             :string           not null
#  prompt_tokens     :integer
#  total_tokens      :integer
#  triggered_by      :integer          default("manual"), not null
#  created_at        :datetime         not null
#  account_id        :bigint           not null
#  conversation_id   :bigint
#  message_id        :bigint
#
# Indexes
#
#  index_auditoria_ai_usage_logs_on_account_feature_created  (account_id,feature,created_at)
#  index_auditoria_ai_usage_logs_on_account_id               (account_id)
#  index_auditoria_ai_usage_logs_on_conversation_id          (conversation_id)
#  index_auditoria_ai_usage_logs_on_message_id               (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#  fk_rails_...  (message_id => messages.id) ON DELETE => nullify
#
class Auditoria::AiUsageLog < ApplicationRecord
  self.table_name = 'auditoria_ai_usage_logs'

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true

  enum :feature, { conversation_analysis: 0, audio_transcription: 1 }
  enum :triggered_by, { manual: 0, batch: 1 }

  validates :model, presence: true
end

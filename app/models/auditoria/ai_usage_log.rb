class Auditoria::AiUsageLog < ApplicationRecord
  self.table_name = 'auditoria_ai_usage_logs'

  belongs_to :account
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true

  enum :feature, { conversation_analysis: 0, audio_transcription: 1 }
  enum :triggered_by, { manual: 0, batch: 1 }

  validates :model, presence: true
end

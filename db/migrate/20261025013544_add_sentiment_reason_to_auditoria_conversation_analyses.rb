class AddSentimentReasonToAuditoriaConversationAnalyses < ActiveRecord::Migration[7.1]
  def change
    add_column :auditoria_conversation_analyses, :sentiment_reason, :text
  end
end

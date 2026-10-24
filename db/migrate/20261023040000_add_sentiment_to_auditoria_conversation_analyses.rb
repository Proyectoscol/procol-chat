class AddSentimentToAuditoriaConversationAnalyses < ActiveRecord::Migration[7.1]
  def change
    add_column :auditoria_conversation_analyses, :sentiment, :string
    add_index :auditoria_conversation_analyses, :sentiment
  end
end

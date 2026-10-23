class AddFeedbackTagsToAuditoriaAdvisorDailySummaries < ActiveRecord::Migration[7.2]
  def change
    add_column :auditoria_advisor_daily_summaries, :feedback_tags, :string, array: true, default: [], null: false
    add_index :auditoria_advisor_daily_summaries, :feedback_tags, using: 'gin'
  end
end

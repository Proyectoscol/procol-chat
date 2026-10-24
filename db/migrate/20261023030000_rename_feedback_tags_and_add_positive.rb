class RenameFeedbackTagsAndAddPositive < ActiveRecord::Migration[7.1]
  def change
    rename_column :auditoria_advisor_daily_summaries, :feedback_tags, :feedback_tags_negative

    add_column :auditoria_advisor_daily_summaries, :feedback_tags_positive, :string, array: true, default: [], null: false
    add_index :auditoria_advisor_daily_summaries, :feedback_tags_positive, using: :gin,
                                                                           name: 'idx_auditoria_advisor_daily_summaries_on_feedback_tags_pos'

    add_column :auditoria_advisor_daily_summaries, :feedback_tags_negative_detail, :jsonb, default: [], null: false
  end
end

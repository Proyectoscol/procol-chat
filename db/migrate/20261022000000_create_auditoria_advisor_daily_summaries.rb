class CreateAuditoriaAdvisorDailySummaries < ActiveRecord::Migration[7.2]
  def change
    create_table :auditoria_advisor_daily_summaries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.date :summary_date, null: false
      t.integer :conversations_count, null: false, default: 0
      t.jsonb :category_counts, null: false, default: {}
      t.jsonb :results, null: false, default: {}
      t.datetime :generated_at

      t.timestamps
    end

    add_index :auditoria_advisor_daily_summaries, [:account_id, :user_id, :summary_date],
              unique: true, name: 'idx_auditoria_advisor_summary_unique'
  end
end

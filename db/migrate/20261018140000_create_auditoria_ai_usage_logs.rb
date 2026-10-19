class CreateAuditoriaAiUsageLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :auditoria_ai_usage_logs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :message, foreign_key: { on_delete: :nullify }
      t.integer :feature, null: false
      t.string :model, null: false
      t.integer :prompt_tokens
      t.integer :completion_tokens
      t.integer :total_tokens
      t.decimal :cost_usd, precision: 10, scale: 6
      t.integer :triggered_by, null: false, default: 0

      t.datetime :created_at, null: false
    end

    add_index :auditoria_ai_usage_logs, [:account_id, :feature, :created_at],
              name: 'index_auditoria_ai_usage_logs_on_account_feature_created'
  end
end

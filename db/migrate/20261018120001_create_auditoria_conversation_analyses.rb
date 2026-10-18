class CreateAuditoriaConversationAnalyses < ActiveRecord::Migration[7.2]
  def change
    create_table :auditoria_conversation_analyses do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.jsonb :results, null: false, default: {}
      t.datetime :analyzed_at

      t.timestamps
    end
  end
end

class CreateAuditoriaAiFieldConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :auditoria_ai_field_configs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.integer :field_order, null: false
      t.string :title, null: false
      t.text :subtitle
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :auditoria_ai_field_configs, [:account_id, :field_order],
              unique: true, name: 'index_auditoria_ai_field_configs_on_account_and_order'
  end
end

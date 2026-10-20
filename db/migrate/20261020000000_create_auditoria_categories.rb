class CreateAuditoriaCategories < ActiveRecord::Migration[7.2]
  def change
    create_table :auditoria_categories do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, null: false
      t.integer :match_type, null: false, default: 0
      t.boolean :is_active, null: false, default: true
      t.text :search_terms
      t.text :instructions

      t.timestamps
    end

    add_index :auditoria_categories, [:account_id, :title], unique: true,
                                                            name: 'index_auditoria_categories_on_account_and_title'
  end
end

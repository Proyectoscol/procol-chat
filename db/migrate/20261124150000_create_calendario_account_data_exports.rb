class CreateCalendarioAccountDataExports < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_account_data_exports do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.jsonb :manifest, null: false, default: {}

      t.timestamps
    end
  end
end

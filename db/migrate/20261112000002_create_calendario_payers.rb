class CreateCalendarioPayers < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_payers do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :calendario_payers, [:account_id, :name], unique: true,
                                                          name: 'index_calendario_payers_on_account_and_name'
  end
end

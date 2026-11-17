class CreateCalendarioProfessionals < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_professionals do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :calendario_professionals, [:account_id, :user_id], unique: true,
                                                                   name: 'index_calendario_professionals_on_account_and_user'
  end
end

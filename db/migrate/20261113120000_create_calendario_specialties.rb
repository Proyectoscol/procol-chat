class CreateCalendarioSpecialties < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_specialties do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :calendario_specialties, [:account_id, :name], unique: true,
                                                               name: 'index_calendario_specialties_on_account_and_name'
  end
end

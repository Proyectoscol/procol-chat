class CreateCalendarioServices < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_services do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :duration_minutes, null: false
      t.string :color
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :calendario_services, [:account_id, :name], unique: true,
                                                            name: 'index_calendario_services_on_account_and_name'
  end
end

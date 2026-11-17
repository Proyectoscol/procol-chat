class CreateCalendarioOpenDays < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_open_days do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :professional, null: false, foreign_key: { to_table: :calendario_professionals, on_delete: :cascade }
      t.references :opened_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.date :date, null: false
      t.integer :time_window, null: false, default: 0
      t.text :notes

      t.timestamps
    end

    add_index :calendario_open_days, [:professional_id, :date, :time_window],
              name: 'index_calendario_open_days_on_professional_date_window'
  end
end

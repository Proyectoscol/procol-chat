class CreateCalendarioWorkingDayOverrides < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_working_day_overrides do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.date :date, null: false
      t.boolean :open, null: false, default: true
      t.string :note

      t.timestamps
    end

    add_index :calendario_working_day_overrides, %i[inbox_id date], unique: true
  end
end

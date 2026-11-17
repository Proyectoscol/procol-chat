class AddBillingFieldsToCalendarioServices < ActiveRecord::Migration[7.1]
  def change
    add_column :calendario_services, :kind, :integer, null: false, default: 0
    add_column :calendario_services, :included_sessions, :integer, null: false, default: 0
    add_column :calendario_services, :base_price, :integer
  end
end

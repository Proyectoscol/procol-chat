class AddInternalToContacts < ActiveRecord::Migration[7.1]
  def change
    add_column :contacts, :internal, :boolean, default: false, null: false
    add_index :contacts, :internal
  end
end

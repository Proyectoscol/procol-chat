class AddDocumentFieldsToContacts < ActiveRecord::Migration[7.1]
  def change
    add_column :contacts, :document_type, :integer
    add_column :contacts, :secondary_phone_number, :string
  end
end

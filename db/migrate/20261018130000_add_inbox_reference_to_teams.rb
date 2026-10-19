class AddInboxReferenceToTeams < ActiveRecord::Migration[7.2]
  def change
    add_reference :teams, :inbox, foreign_key: { on_delete: :cascade }, index: { unique: true }
  end
end

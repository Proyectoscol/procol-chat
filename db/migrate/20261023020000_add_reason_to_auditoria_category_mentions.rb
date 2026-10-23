class AddReasonToAuditoriaCategoryMentions < ActiveRecord::Migration[7.2]
  def change
    add_column :auditoria_category_mentions, :reason, :string
  end
end

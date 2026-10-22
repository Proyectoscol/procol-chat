class AddInboxIdsToAuditoriaCategories < ActiveRecord::Migration[7.2]
  def change
    # Vacio = aplica a todos los inboxes de la cuenta (comportamiento actual,
    # sin cambios para ninguna categoria existente). Una subcategoria solo
    # puede restringirse a un subconjunto del scope de su padre -- ver
    # Auditoria::Category#inbox_ids_within_parent_scope.
    add_column :auditoria_categories, :inbox_ids, :integer, array: true, default: [], null: false
    add_index :auditoria_categories, :inbox_ids, using: 'gin'
  end
end

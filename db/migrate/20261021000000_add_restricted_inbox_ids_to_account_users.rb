class AddRestrictedInboxIdsToAccountUsers < ActiveRecord::Migration[7.2]
  def change
    # Vacio = sin restriccion (comportamiento actual, sin cambios para ningun
    # admin existente). No vacio + role administrator = acceso limitado a
    # esos inboxes en conversaciones/agentes/reportes/auditoria -- ver
    # AccountUser#inbox_restricted?.
    add_column :account_users, :restricted_inbox_ids, :integer, array: true, default: [], null: false
    add_index :account_users, :restricted_inbox_ids, using: 'gin'
  end
end

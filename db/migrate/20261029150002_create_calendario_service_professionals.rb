class CreateCalendarioServiceProfessionals < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_service_professionals do |t|
      t.references :service, null: false, foreign_key: { to_table: :calendario_services, on_delete: :cascade }
      t.references :professional, null: false, foreign_key: { to_table: :calendario_professionals, on_delete: :cascade }

      t.timestamps
    end

    add_index :calendario_service_professionals, [:service_id, :professional_id], unique: true,
                                                                                    name: 'index_calendario_svc_profs_on_service_and_professional'
  end
end

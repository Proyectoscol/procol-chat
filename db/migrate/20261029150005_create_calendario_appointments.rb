class CreateCalendarioAppointments < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_appointments do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :professional, null: false, foreign_key: { to_table: :calendario_professionals, on_delete: :cascade }
      t.references :service, null: false, foreign_key: { to_table: :calendario_services, on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :status, null: false, default: 0
      t.text :notes

      t.timestamps
    end

    add_index :calendario_appointments, [:account_id, :starts_at]

    # Rechaza a nivel de base de datos dos citas que se superpongan para el
    # mismo profesional (ver auditoria A3 del eng-review: un indice unico
    # sobre (professional_id, starts_at) solo bloquea el mismo instante
    # exacto, no un rango superpuesto -- el race condition real necesita un
    # EXCLUDE USING gist). La condicion WHERE excluye canceladas (4) para
    # que un horario cancelado libere el slot para un nuevo agendamiento.
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          ALTER TABLE calendario_appointments
          ADD CONSTRAINT calendario_appointments_no_overlap
          EXCLUDE USING gist (
            professional_id WITH =,
            tsrange(starts_at, ends_at) WITH &&
          ) WHERE (status <> 4)
        SQL
      end

      dir.down do
        execute 'ALTER TABLE calendario_appointments DROP CONSTRAINT calendario_appointments_no_overlap'
      end
    end
  end
end

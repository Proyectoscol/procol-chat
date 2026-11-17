# Pedido explicito del usuario: las especialidades del consultorio son
# Urología y Ginecología, y todo profesional queda ligado a una. Se siembran
# aqui (no solo en db/seeds.rb) para que cualquier cuenta que YA tenga
# profesionales creados (como los datos de prueba de este ambiente) quede
# consistente sin que un administrador tenga que ir fila por fila. Usa SQL
# plano (no los modelos de ActiveRecord) porque las migraciones de datos no
# deben depender de clases de la app que pueden cambiar despues.
class SeedCalendarioSpecialtiesAndBackfillProfessionals < ActiveRecord::Migration[7.1]
  def up
    account_ids = select_values('SELECT DISTINCT account_id FROM calendario_professionals')
    return if account_ids.empty?

    account_ids.each do |account_id|
      %w[Urología Ginecología].each do |name|
        execute <<-SQL.squish
          INSERT INTO calendario_specialties (account_id, name, active, created_at, updated_at)
          SELECT #{account_id}, #{quote(name)}, TRUE, NOW(), NOW()
          WHERE NOT EXISTS (
            SELECT 1 FROM calendario_specialties WHERE account_id = #{account_id} AND name = #{quote(name)}
          )
        SQL
      end

      execute <<-SQL.squish
        UPDATE calendario_professionals
        SET specialty_id = (
          SELECT id FROM calendario_specialties WHERE account_id = #{account_id} AND name = 'Urología'
        )
        WHERE account_id = #{account_id} AND specialty_id IS NULL
      SQL
    end
  end

  def down
    # No-op: no vale la pena deshacer datos sembrados, y borrar
    # especialidades ya asignadas rompiera citas/filtros que las usen.
  end
end

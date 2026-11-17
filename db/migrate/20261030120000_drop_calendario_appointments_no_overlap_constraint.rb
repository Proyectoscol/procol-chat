class DropCalendarioAppointmentsNoOverlapConstraint < ActiveRecord::Migration[7.1]
  def up
    execute 'ALTER TABLE calendario_appointments DROP CONSTRAINT IF EXISTS calendario_appointments_no_overlap'
  end

  def down
    execute <<-SQL.squish
      ALTER TABLE calendario_appointments
      ADD CONSTRAINT calendario_appointments_no_overlap
      EXCLUDE USING gist (
        professional_id WITH =,
        tsrange(starts_at, ends_at) WITH &&
      ) WHERE (status <> 4)
    SQL
  end
end

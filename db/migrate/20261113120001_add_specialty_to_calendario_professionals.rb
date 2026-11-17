# Nullable a proposito: un profesional existente puede quedar sin
# especialidad hasta que un administrador la asigne -- la exigencia de
# "todo profesional nuevo requiere especialidad" vive en la validacion del
# modelo, no en una constraint de BD que romperia filas viejas. El backfill
# de los datos de prueba va en una migracion aparte (ver
# SeedCalendarioSpecialtiesAndBackfillProfessionals) porque necesita que las
# especialidades ya existan.
class AddSpecialtyToCalendarioProfessionals < ActiveRecord::Migration[7.1]
  def change
    add_reference :calendario_professionals, :specialty, foreign_key: { to_table: :calendario_specialties, on_delete: :nullify }
  end
end

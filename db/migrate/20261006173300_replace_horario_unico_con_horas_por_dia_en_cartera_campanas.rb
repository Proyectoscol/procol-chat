# Reemplaza el rango unico hora_inicio/hora_fin (aplicado igual a todos los
# dias activos) por una hora exacta de envio por cada dia de la semana -
# lo que pidio el usuario: "lunes a las 9, sabado a las 2pm, lo que yo
# defina", en vez de una ventana ambigua de varias horas donde no es claro
# a que momento se manda el mensaje. Ver seccion 1 del plan "Claridad de
# campanas y Agente IA".
# rubocop:disable Style/OneClassPerFile -- clase AR local al backfill, patron estandar de migraciones Rails
class ReplaceHorarioUnicoConHorasPorDiaEnCarteraCampanas < ActiveRecord::Migration[7.1]
  class CampanaDeMigracion < ActiveRecord::Base
    self.table_name = 'cartera_campanas'
  end

  def up
    add_column :cartera_campanas, :horas_envio, :jsonb, null: false, default: {}
    CampanaDeMigracion.reset_column_information

    # Backfill via ActiveRecord (no SQL crudo): hora_inicio es una columna
    # :time zone-aware (Rails la guarda desplazada a UTC y la muestra
    # convertida a la zona de la app) - leer el valor crudo con to_char()
    # en SQL habria capturado la hora UTC, no la hora local que el usuario
    # configuro y que horas_envio necesita guardar tal cual (se compara
    # directo contra Time.current.seconds_since_midnight, ya en hora
    # local). La unica hora que existia antes era hora_inicio, asi que
    # cada dia ya activo en dias_envio arranca con esa hora - editable
    # luego desde Ajustes, dia por dia.
    CampanaDeMigracion.find_each do |campana|
      next if campana.dias_envio.blank?

      hora = campana.hora_inicio.strftime('%H:%M')
      campana.update!(horas_envio: campana.dias_envio.index_with { hora })
    end

    remove_column :cartera_campanas, :hora_inicio
    remove_column :cartera_campanas, :hora_fin
  end

  def down
    add_column :cartera_campanas, :hora_inicio, :time, default: '07:00'
    add_column :cartera_campanas, :hora_fin, :time, default: '19:00'
    change_column_null :cartera_campanas, :hora_inicio, false
    change_column_null :cartera_campanas, :hora_fin, false
    CampanaDeMigracion.reset_column_information

    # Misma razon que en up: asignar por atributo (no SQL crudo) para que
    # Rails aplique el mismo cast zone-aware que aplicaria a cualquier
    # escritura normal de hora_inicio/hora_fin.
    CampanaDeMigracion.find_each do |campana|
      horas = campana.horas_envio.values
      next if horas.empty?

      campana.hora_inicio = horas.min
      campana.hora_fin = horas.max
      campana.save!(validate: false)
    end

    remove_column :cartera_campanas, :horas_envio
  end
end
# rubocop:enable Style/OneClassPerFile

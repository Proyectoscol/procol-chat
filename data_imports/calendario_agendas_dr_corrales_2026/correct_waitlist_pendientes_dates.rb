# Bug encontrado 2026-11-25: las entradas de Calendario::WaitlistEntry
# importadas desde la hoja PENDIENTES de PARTICULARES 2026.xlsx (import de
# una sesion anterior, 2026-11-24) quedaron con created_at = momento del
# import, no la fecha real de la columna FECHA del Excel -- por eso la UI
# mostraba "0 dias en espera" para solicitudes de hace meses. Se identifica
# cada fila por el numero exacto en sus notas
# ("[Importado de Excel: PENDIENTES fila N]") y se corrige SOLO created_at,
# usando pendientes_fila_fecha.csv (generado leyendo la columna FECHA de la
# hoja PENDIENTES directamente).
#
# Uso:
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/correct_waitlist_pendientes_dates.rb
#
# APPLY=1 para persistir (si no, dry-run con ROLLBACK, igual patron que
# correct_appointments_batch4.rb). ALLOW_PROD=1 requerido en produccion.

raise 'Falta ALLOW_PROD=1 para correr en produccion' if Rails.env.production? && ENV['ALLOW_PROD'] != '1'

require 'csv'

IMPORT_DIR = Pathname.new(__dir__)
ACCOUNT_ID = (ENV['ACCOUNT_ID'] || 1).to_i
APPLY = ENV['APPLY'] == '1'
BOGOTA = ActiveSupport::TimeZone['America/Bogota']

fecha_by_fila = {}
CSV.foreach(IMPORT_DIR.join('pendientes_fila_fecha.csv'), headers: true) do |row|
  fecha_by_fila[row['fila'].to_i] = row['fecha']
end

account = Account.find(ACCOUNT_ID)
puts "== Correccion created_at WaitlistEntry (PENDIENTES) -- cuenta ##{account.id} =="
puts(APPLY ? '** APPLY=1 **' : '** DRY_RUN **')

corrected = []
no_fila_match = []
no_fecha_in_sheet = []

ActiveRecord::Base.transaction do
  account.calendario_waitlist_entries.where("notes LIKE ?", '%PENDIENTES fila%').find_each do |entry|
    match = entry.notes.match(/PENDIENTES fila (\d+)\]/)
    if match.nil?
      no_fila_match << entry.id
      next
    end
    fila = match[1].to_i
    fecha = fecha_by_fila[fila]
    if fecha.nil?
      no_fecha_in_sheet << "id=#{entry.id} fila=#{fila}"
      next
    end
    real_created_at = BOGOTA.parse(fecha)
    next if entry.created_at.to_date == real_created_at.to_date

    entry.update_columns(created_at: real_created_at) if APPLY
    corrected << "id=#{entry.id} fila=#{fila}: #{entry.created_at.to_date} -> #{real_created_at.to_date}"
  end
  raise ActiveRecord::Rollback unless APPLY
end

puts "Corregidas: #{corrected.size}"
puts "Sin numero de fila en notas: #{no_fila_match.size}"
puts "Fila sin fecha en la hoja PENDIENTES: #{no_fecha_in_sheet.size}"
corrected.first(10).each { |l| puts "  #{l}" }

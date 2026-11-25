# Dos typos de fecha en el Excel confirmados con el usuario 2026-11-25:
#
# 1. 5 bloques de Dr. Gaviria dicen año "2025" en el titulo, pero el dia de
#    semana que tambien escribieron (ej. "MIERCOLES 07 DE ENERO") solo
#    coincide matematicamente si el año es 2026 -- confirmado, se corrige
#    sumando 1 año (43 citas).
# 2. Un bloque de Dra. Cano dice "MARTES 27 DE SEPTIEMBRE DE 2026" pero esa
#    fecha cae domingo -- el usuario confirmo que el dia de semana es el
#    dato correcto (de verdad fue un martes), la fecha se mueve al martes
#    mas cercano, 29 de septiembre (6 citas, +2 dias).
#
# Dry-run por defecto, APPLY=1 persiste. ALLOW_PROD=1 en produccion.

raise 'Falta ALLOW_PROD=1 para correr en produccion' if Rails.env.production? && ENV['ALLOW_PROD'] != '1'

APPLY = ENV['APPLY'] == '1'
BOGOTA = ActiveSupport::TimeZone['America/Bogota']
account = Account.find((ENV['ACCOUNT_ID'] || 1).to_i)

def shift(account, professional_name, date_range, delta, label, apply:)
  professional = account.calendario_professionals.find_by(name: professional_name)
  raise "no se encontro #{professional_name}" if professional.blank?

  appts = account.calendario_appointments.where(professional_id: professional.id, starts_at: date_range)
  puts "#{label}: #{appts.count} citas"
  appts.find_each do |a|
    a.update_columns(starts_at: a.starts_at + delta, ends_at: a.ends_at + delta) if apply
  end
end

puts(APPLY ? '** APPLY=1 **' : '** DRY_RUN **')

GAVIRIA_2025_DAYS = [
  Date.new(2025, 1, 7), Date.new(2025, 1, 9), Date.new(2025, 5, 1),
  Date.new(2025, 6, 19), Date.new(2025, 6, 26)
].freeze

GAVIRIA_2025_DAYS.each do |d|
  range = BOGOTA.parse(d.iso8601)..BOGOTA.parse(d.iso8601).end_of_day
  shift(account, 'Dr. Gaviria', range, 1.year, "Gaviria #{d.iso8601} -> #{d.next_year.iso8601}", apply: APPLY)
end

cano_day = Date.new(2026, 9, 27)
cano_range = BOGOTA.parse(cano_day.iso8601)..BOGOTA.parse(cano_day.iso8601).end_of_day
shift(account, 'Dra. Cano', cano_range, 2.days, "Cano #{cano_day.iso8601} -> #{(cano_day + 2).iso8601}", apply: APPLY)

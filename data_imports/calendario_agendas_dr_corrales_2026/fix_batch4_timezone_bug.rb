# BUG REAL encontrado 2026-11-25 (mismo dia del deploy): correct_appointments_batch4.rb
# uso `Time.zone.parse` (Time.zone de la app es UTC) en vez de
# `BOGOTA.parse` para `starts_at` al CREAR citas nuevas -- la hora del
# Excel (hora local de Bogota, ej. "09:00") quedo guardada como si fuera
# UTC, 5 horas antes de la hora real (09:00 Bogota -> 09:00 UTC = 04:00
# Bogota). Afecta SOLO las citas CREADAS por ese script (no las
# corregidas -- esas nunca tocaron starts_at), identificables por el tag
# fijo en notes.
#
# Corrige starts_at Y ends_at (+5 horas) de toda cita con ese tag. Dry-run
# por defecto (APPLY=1 para persistir), ALLOW_PROD=1 requerido en
# produccion -- mismo patron que el resto de scripts de esta sesion.

raise 'Falta ALLOW_PROD=1 para correr en produccion' if Rails.env.production? && ENV['ALLOW_PROD'] != '1'

APPLY = ENV['APPLY'] == '1'
TAG = 'Importado fase 3 batch 4'.freeze

account = Account.find((ENV['ACCOUNT_ID'] || 1).to_i)
affected = Calendario::Appointment.where(account_id: account.id).where('notes LIKE ?', "%#{TAG}%")
puts "Citas afectadas: #{affected.count}"
puts(APPLY ? '** APPLY=1: esto SI persiste cambios reales **' : '** DRY_RUN: no se persiste nada **')

sample = affected.order(:id).limit(5).map { |a| "id=#{a.id} starts_at=#{a.starts_at} -> #{a.starts_at + 5.hours}" }
puts sample

if APPLY
  affected.find_each do |appointment|
    appointment.update_columns(starts_at: appointment.starts_at + 5.hours, ends_at: appointment.ends_at + 5.hours)
  end
  puts "Corregidas: #{affected.count}"
end

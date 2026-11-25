# Bug de origen en el Excel (NO de este codigo): la hora de muchas citas
# se escribio como "1:00"/"2:00".../"5:00" sin especificar AM/PM, y Excel
# las guarda como madrugada por defecto. El hueco casi vacio en la tarde
# (13:00-15:00, solo 18 citas de 3170) confirma el patron: son PM, no AM
# -- consultorio de la tarde. Confirmado con el usuario 2026-11-25.
#
# Afecta tanto las citas CREADAS hoy (fase 3 batch 4) como las que ya
# existian en produccion de una carga anterior -- por eso este script NO
# usa el tag de notas (como fix_batch4_timezone_bug.rb), sino que vuelve a
# matchear cada fila del Excel contra Calendario::Appointment por
# contacto (telefono) + profesional + MISMO DIA calendario (misma llave
# que correct_appointments_batch4.rb), y solo toca la cita si su hora
# actual (en zona Bogota) sigue cayendo en el rango sospechoso 01:00-05:59
# -- asi nunca se le suma 12h dos veces ni se toca una cita que ya esta bien.
#
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/fix_batch4_ampm_bug.rb
#   APPLY=1 ... (persiste). ALLOW_PROD=1 requerido en produccion.

raise 'Falta ALLOW_PROD=1 para correr en produccion' if Rails.env.production? && ENV['ALLOW_PROD'] != '1'

require 'csv'

IMPORT_DIR = Pathname.new(__dir__)
ACCOUNT_ID = (ENV['ACCOUNT_ID'] || 1).to_i
APPLY = ENV['APPLY'] == '1'
BOGOTA = ActiveSupport::TimeZone['America/Bogota']
SOURCE_FILES = %w[normalizado_corrales.csv normalizado_cano.csv normalizado_particulares.csv].freeze
SUSPECT_HOURS = (1..5).freeze

PROFESSIONAL_NAME = {
  'DR CORRALES' => 'Dr. Corrales', 'DR DEVIA' => 'Dr. Devia', 'DR VELEZ' => 'Dr. Velez',
  'DR GAVIRIA' => 'Dr. Gaviria', 'DRA ESPAÑA' => 'Dra. España', 'DRA CANO' => 'Dra. Cano',
  'DR ESPITIA' => 'Dr. Espitia', 'TERAPIAS' => 'Terapias'
}.freeze

account = Account.find(ACCOUNT_ID)
puts "== Fix AM/PM batch4 -- cuenta ##{account.id} =="
puts(APPLY ? '** APPLY=1 **' : '** DRY_RUN **')

rows = SOURCE_FILES.flat_map { |f| CSV.foreach(IMPORT_DIR.join(f), headers: true, encoding: 'bom|utf-8').map(&:to_h) }
contacts_by_phone = {}
account.contacts.where.not(phone_number: nil).find_each { |c| contacts_by_phone[c.phone_number] = c }
account.contacts.where.not(secondary_phone_number: nil).find_each { |c| contacts_by_phone[c.secondary_phone_number] ||= c }
professionals_by_name = account.calendario_professionals.index_by(&:name)

fixed = []
no_contact = []
no_appointment = []
already_ok = []

rows.each do |row|
  next if row['cita_fecha_hora'].blank?

  hour = row['cita_fecha_hora'][11, 2].to_i
  next unless SUSPECT_HOURS.cover?(hour)

  professional = professionals_by_name[PROFESSIONAL_NAME[row['profesional']]]
  next if professional.blank?

  contact = [row['telefono_principal'], row['telefono_secundario']].compact_blank.map { |p| contacts_by_phone[p] }.compact.first
  if contact.blank?
    no_contact << row
    next
  end

  day = BOGOTA.parse(row['cita_fecha_hora']).to_date
  appointment = Calendario::Appointment.where(
    account_id: account.id, contact_id: contact.id, professional_id: professional.id, starts_at: day.all_day
  ).first
  if appointment.blank?
    no_appointment << row
    next
  end

  current_hour = appointment.starts_at.in_time_zone('America/Bogota').hour
  unless SUSPECT_HOURS.cover?(current_hour)
    already_ok << row
    next
  end

  new_starts_at = appointment.starts_at + 12.hours
  new_ends_at = appointment.ends_at + 12.hours
  appointment.update_columns(starts_at: new_starts_at, ends_at: new_ends_at) if APPLY
  fixed << "#{contact.name} #{day} #{current_hour}:xx -> #{current_hour + 12}:xx (id=#{appointment.id})"
end

puts "Corregidas: #{fixed.size}"
puts "Ya estaban bien (hora actual fuera de 1-5am): #{already_ok.size}"
puts "Sin contacto: #{no_contact.size}"
puts "Sin cita encontrada ese dia: #{no_appointment.size}"
fixed.first(15).each { |l| puts "  #{l}" }

# Segunda pasada del fix de AM/PM (ver fix_batch4_ampm_bug.rb) -- esas 10
# citas que quedaron sin corregir tenian el contacto SIN telefono (match
# por telefono nunca las encontro) o un telefono que no calzaba exacto.
# Aqui se matchea directo por CEDULA (identifier), no por telefono.
#
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/fix_batch4_ampm_remaining.rb
#   APPLY=1 para persistir. ALLOW_PROD=1 en produccion.

raise 'Falta ALLOW_PROD=1 para correr en produccion' if Rails.env.production? && ENV['ALLOW_PROD'] != '1'

require 'csv'

IMPORT_DIR = Pathname.new(__dir__)
APPLY = ENV['APPLY'] == '1'
BOGOTA = ActiveSupport::TimeZone['America/Bogota']
SOURCE_FILES = %w[normalizado_corrales.csv normalizado_cano.csv normalizado_particulares.csv].freeze
SUSPECT_HOURS = (1..5).freeze

PROFESSIONAL_NAME = {
  'DR CORRALES' => 'Dr. Corrales', 'DR DEVIA' => 'Dr. Devia', 'DR VELEZ' => 'Dr. Velez',
  'DR GAVIRIA' => 'Dr. Gaviria', 'DRA ESPAÑA' => 'Dra. España', 'DRA CANO' => 'Dra. Cano',
  'DR ESPITIA' => 'Dr. Espitia', 'TERAPIAS' => 'Terapias'
}.freeze

account = Account.find((ENV['ACCOUNT_ID'] || 1).to_i)
puts(APPLY ? '** APPLY=1 **' : '** DRY_RUN **')

rows = SOURCE_FILES.flat_map { |f| CSV.foreach(IMPORT_DIR.join(f), headers: true, encoding: 'bom|utf-8').map(&:to_h) }
contacts_by_doc = account.contacts.where.not(identifier: nil).index_by(&:identifier)
professionals_by_name = account.calendario_professionals.index_by(&:name)

fixed = []
rows.each do |row|
  next if row['cita_fecha_hora'].blank?

  hour = row['cita_fecha_hora'][11, 2].to_i
  next unless SUSPECT_HOURS.cover?(hour)

  professional = professionals_by_name[PROFESSIONAL_NAME[row['profesional']]]
  next if professional.blank?

  contact = contacts_by_doc[row['cedula']]
  next if contact.blank?

  day = BOGOTA.parse(row['cita_fecha_hora']).to_date
  appointment = Calendario::Appointment.where(
    account_id: account.id, contact_id: contact.id, professional_id: professional.id, starts_at: day.all_day
  ).first
  next if appointment.blank?

  current_hour = appointment.starts_at.in_time_zone('America/Bogota').hour
  next unless SUSPECT_HOURS.cover?(current_hour)

  if APPLY
    appointment.update_columns(starts_at: appointment.starts_at + 12.hours, ends_at: appointment.ends_at + 12.hours)
  end
  fixed << "#{contact.name} #{day} #{current_hour}:xx -> #{current_hour + 12}:xx (id=#{appointment.id})"
end

puts "Corregidas: #{fixed.size}"
fixed.each { |l| puts "  #{l}" }

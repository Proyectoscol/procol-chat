# Fase 3 del batch 4 (agendas Corrales/Cano/Particulares 2026): corrige el
# created_at (y estado/monto cuando hay evidencia) de citas YA existentes en
# el sistema, o crea las que falten -- a diferencia de import_to_local.rb
# (fase 1-2), este script NUNCA borra nada: solo corrige o agrega.
#
# Uso:
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/correct_appointments_batch4.rb
#
# Variables de entorno opcionales:
#   ACCOUNT_ID=1   (cuenta destino, default 1)
#   APPLY=1        (sin esto, SIEMPRE corre dentro de una transaccion con
#                   ROLLBACK al final -- reporta que haria, no persiste nada)
#
# Decisiones ya confirmadas con el usuario (ver sesion 2026-11-24/25):
#   - Llave de match para "corregir vs crear": contacto (por telefono) +
#     profesional + MISMO DIA calendario. 0 matches = crear, 1 = corregir,
#     2+ = NO se toca, queda en el reporte para revision manual.
#   - Contacto: solo se linkea a un Contact YA EXISTENTE por telefono
#     (principal o secundario). Nunca se crea un contacto nuevo aqui -- el
#     riesgo de duplicar identidades es mayor que el beneficio; sin contacto
#     encontrado, la fila queda en el reporte, no se crea la cita.
#   - Servicio: solo auto-mapeo de coincidencias claras (ver SERVICE_RULES).
#     Cualquier "procedimiento" que no calce con ninguna regla queda SIN
#     aplicar, listado para que el usuario confirme el mapeo.

# Para produccion: requiere ALLOW_PROD=1 explicito, ademas de APPLY=1 para
# persistir -- dos banderas distintas a proposito, asi un DRY_RUN accidental
# en el ambiente equivocado nunca persiste nada (la transaccion igual hace
# rollback salvo que APPLY=1 este tambien presente).
raise 'Falta ALLOW_PROD=1 para correr en produccion' if Rails.env.production? && ENV['ALLOW_PROD'] != '1'
raise 'Ambiente no reconocido (solo development o production)' unless Rails.env.development? || Rails.env.production?

require 'csv'

IMPORT_DIR = Pathname.new(__dir__)
ACCOUNT_ID = (ENV['ACCOUNT_ID'] || 1).to_i
APPLY = ENV['APPLY'] == '1'
BOGOTA = ActiveSupport::TimeZone['America/Bogota']
SOURCE_FILES = %w[normalizado_corrales.csv normalizado_cano.csv normalizado_particulares.csv].freeze

PROFESSIONAL_SPECIALTY = {
  'DR CORRALES' => ['Dr. Corrales', :urologia],
  'DR DEVIA' => ['Dr. Devia', :urologia],
  'DR VELEZ' => ['Dr. Velez', :urologia],
  'DR GAVIRIA' => ['Dr. Gaviria', :urologia],
  'DRA ESPAÑA' => ['Dra. España', :urologia],
  'DRA CANO' => ['Dra. Cano', :ginecologia],
  # Nuevos, confirmados con el usuario (ver AskUserQuestion 2026-11-25):
  'DR ESPITIA' => ['Dr. Espitia', :ginecologia],
  'TERAPIAS' => ['Terapias', :ginecologia],
}.freeze

# Orden de evaluacion importa: la primera regla que calce (substring sobre
# el procedimiento ya normalizado, sin tildes/espacios extra) gana. Todo lo
# que no calce con ninguna regla se deja SIN mapear (ver unmapped_services).
SERVICE_RULES = [
  # Consulta: variantes con "+CIT*/VPH" (citologia/VPH tomado en la misma
  # consulta) van al mismo servicio -- el catalogo no distingue ese add-on.
  [/^CONSULTA|^CONSSULTA|^COSULTA|^CONS\+|^CONSUL\+|^CONSU\+|^CONSS\+|^CITOL\+VPH|^CIT\+VPH|^TELE-?CONSULTA/, 'Consulta'],
  [/^CONTROL|^CONTRO\b|^CCONTROL|^POST|^HISTERECT|^VALORACION CX|^SURA POLIZA CONTROL|^CONT CIST/, 'Control'],
  [/^CISTOSCOPIA|^CISTOCOPIA|^CISTOSSCOPIA|^CITOSCOPIA|^CIST RET|^CISTOS RET/, 'Cistoscopia'],
  [/^COLPOSCOPIA|^COLP OCT/, 'Colposcopia'], # nuevo, ver SERVICE_DEFAULTS
  [/^TERAPIAS|^TECARPERAPIA|^TECARTERAPIA/, 'Terapias'], # nuevo
  [/^RET[A-Z]*\.?\s?CAT[AE]T|^RETIRO T\b/, 'Retiro de cateter'], # cubre CATETER/CATATER/CATETR (typos vistos)
  [/^ADENECTOMIA\+MORCELACION/, 'Adenectomia + Morcelacion'], # nuevo
  [/^VASECTOMIA/, 'Vasectomia'],
  [/^BX PROSTATA|^BIOPSIA (DE )?PROSTATA/, 'Biopsia de prostata'],
  [/^CONIZACION|^CONO\+VAPOR/, 'Conizacion'],
  [/^SEXOLOGIA/, 'Sexologia'],
  [/^LITOTRICIA/, 'Litotricia'],
  [/^PESARIO/, 'Pesario'],
  [/^CAUTERIZACION|^FULGUR/, 'Cauterizacion'], # fulguracion es tecnicamente cauterizacion
  [/^INSER.*MIRENA/, 'Inserción Mirena'], # nuevo, confirmado con el usuario 2026-11-25
  [/^RES\.?\s?POLIPO CUELLO UTERO/, 'Resección de pólipo cervical'], # nuevo, idem
].freeze

# Igual patron que import_to_local.rb -- duraciones RAZONABLES pero NO
# confirmadas por la clinica, marcadas en el reporte para que se ajusten.
SERVICE_DEFAULTS = {
  'Colposcopia' => { duration_minutes: 20, kind: :procedure, color: '#C4BD97' },
  'Terapias' => { duration_minutes: 30, kind: :procedure, color: '#B2A2C7' },
  'Adenectomia + Morcelacion' => { duration_minutes: 45, kind: :procedure, color: '#948A54' },
  'Inserción Mirena' => { duration_minutes: 20, kind: :procedure, color: '#E6B9B8' },
  'Resección de pólipo cervical' => { duration_minutes: 20, kind: :procedure, color: '#D99694' },
}.freeze

# Typos/variantes vistas en los 3 CSV -> nombre real del payer en catalogo.
# Todo lo que no resuelva por aqui NI por match exacto normalizado queda
# sin payer (nil), listado en unmapped_payers -- nunca se crea un payer
# nuevo a ciegas por un typo.
PAYER_ALIASES = {
  'PARTICULAAR' => 'Particular', 'PARTICCULAR' => 'Particular', 'PARTICU' => 'Particular',
  'PARTICULARES' => 'Particular',
  'COLSSANITAS' => 'Colsanitas',
  'SURAA POLIZA' => 'Sura Poliza', 'SURA PLIZA' => 'Sura Poliza', 'SURA' => 'Sura Eps',
  'UNNISER' => 'Unisser',
  'REDVITAL' => 'Red Vital',
  'SOS BINESTAR' => 'Sos Bienestar',
  'SOS QUIMBAYAA' => 'Sos Quimbaya',
  'MEDPPLUS' => 'Medplus',
  'SEG BOLIVAR' => 'Seguros Bolivar',
  'SERVI HUMANO' => 'Serv Humano',
  'SENTIR' => 'Sentir Humano',
  'PIJAOS SALUD' => 'Pijao Salud', 'PIJAO SALUD' => 'Pijao Salud',
  'ROSALES' => 'Los Rosales',
  'SANITAS PREMIUM' => 'Sanitas',
  'SENT. HUMAANO' => 'Sentir Humano', 'SENT HUMANO' => 'Sentir Humano',
  'PREVISEER' => 'Previser',
  'PARTICULRA' => 'Particular',
  'SAALUD TOTAL' => 'Salud Total',
  # Payer nuevo confirmado con el usuario 2026-11-25 (no existia en el
  # catalogo de 45 EPS): se mapea a si mismo para que ensure_payer_by_name
  # lo cree una sola vez, igual que cualquier alias normal.
  'SOS PRIVILEGIO' => 'Sos Privilegio',
}.freeze

# Prefijo seguido de texto suelto (telefono, nota de control, numero de
# plan) pegado por error de digitacion -- se resuelve por la PRIMERA
# palabra si esa palabra sola ya es un payer real conocido.
PAYER_PREFIX_ALIASES = {
  'LOS ROSALES' => 'Los Rosales', 'PREVISER' => 'Previser',
}.freeze

def normalize(text)
  text.to_s.strip.upcase
      .gsub(/[ÁÀÂ]/, 'A').gsub(/[ÉÈÊ]/, 'E').gsub(/[ÍÌÎ]/, 'I').gsub(/[ÓÒÔ]/, 'O').gsub(/[ÚÙÛ]/, 'U')
      .gsub(/\s+/, ' ')
end

def resolve_service_name(raw_procedimiento)
  normalized = normalize(raw_procedimiento)
  _, service_name = SERVICE_RULES.find { |regex, _| regex.match?(normalized) }
  service_name
end

def resolve_payer_name(raw_entidad, known_payer_names)
  normalized = normalize(raw_entidad)
  return nil if normalized.blank? || normalized == 'CONSULTA' # dato mal ubicado, no es un payer real

  # Variante con sufijo de plan pegado (ej. "MEDPLUS CELESTE") -- se queda
  # con la primera palabra conocida de payer si el resto no calza exacto.
  return known_payer_names[normalized] if known_payer_names.key?(normalized)
  return PAYER_ALIASES[normalized] if PAYER_ALIASES.key?(normalized)

  first_word = normalized.split(' ').first
  return first_word.capitalize if known_payer_names.key?(first_word) && %w[MEDPLUS FOMAG SURA].include?(first_word)

  PAYER_PREFIX_ALIASES.each { |prefix, name| return name if normalized.start_with?(prefix) }
  nil
end

def ensure_professional(account, specialties, raw_name)
  name, specialty_key = PROFESSIONAL_SPECIALTY.fetch(raw_name) { raise "profesional sin mapeo: #{raw_name.inspect}" }
  professional = account.calendario_professionals.find_or_create_by!(name: name) do |p|
    p.specialty = specialties.fetch(specialty_key)
  end
  professional.update!(active: true) unless professional.active
  professional
end

def ensure_service(account, name)
  account.calendario_services.find_by(name: name) ||
    account.calendario_services.create!(
      name: name, **SERVICE_DEFAULTS.fetch(name, { duration_minutes: 20, kind: :consultation, color: '#A5A5A5' })
    )
end

def ensure_service_professional_link(service, professional)
  return if professional.services.exists?(id: service.id)

  Calendario::ServiceProfessional.create!(service: service, professional: professional)
end

def find_contact_by_phone(contacts_by_phone, row)
  [row['telefono_principal'], row['telefono_secundario']].compact_blank.each do |phone|
    contact = contacts_by_phone[phone]
    return contact if contact
  end
  nil
end

PAYER_KIND_HINTS = { 'PARTICULAR' => :particular, 'SURA POLIZA' => :poliza }.freeze

def payer_kind_for(name)
  return PAYER_KIND_HINTS[name] if PAYER_KIND_HINTS.key?(name)
  return :poliza if name.include?('POLIZA')
  return :prepagada if name.include?('PREPAGADA')

  :eps
end

# OJO: a diferencia de un ensure_payer "ciego" (titlecase + create!, como
# en import_to_local.rb), aqui el nombre YA viene resuelto por
# resolve_payer_name -- solo payers reales del catalogo o alias
# explicitamente revisados (ver PAYER_ALIASES/PAYER_PREFIX_ALIASES) llegan
# hasta aqui. Un typo sin alias nunca crea un payer nuevo, queda sin payer.
def ensure_payer_by_name(account, resolved_name)
  return nil if resolved_name.blank?

  account.calendario_payers.find_or_create_by!(name: resolved_name) { |p| p.kind = payer_kind_for(resolved_name.upcase) }
end

# Paciente con telefono en el Excel que nunca escribio por WhatsApp (no
# existe como Contact en absoluto) -- confirmado con el usuario 2026-11-25:
# se crea el contacto (mismo patron que import_to_local.rb), para que sus
# citas se puedan corregir/crear en el resto del script con normalidad.
E164_RE = /\A\+\d{10,15}\z/

def create_contact_from_row(account, row, known_payer_names)
  payer = ensure_payer_by_name(account, resolve_payer_name(row['entidad'], known_payer_names))
  # El Excel a veces trae un telefono sin normalizar bien (ej. 11 digitos
  # sin "+57") en principal pero uno valido en secundario -- se usa el
  # primer telefono VALIDO como principal en vez de dejar que el invalido
  # tumbe el guardado completo del contacto (ver VALENTINA ARROYAVE JIMENEZ).
  valid_phones = [row['telefono_principal'], row['telefono_secundario']].compact_blank.select { |p| E164_RE.match?(p) }
  contact = account.contacts.new(
    name: row['nombre'].strip, identifier: row['cedula'].presence,
    phone_number: valid_phones[0], secondary_phone_number: valid_phones[1],
    payer: payer
  )
  return contact if contact.save

  # Mismo fallback que import_to_local.rb: telefono ya tomado por otro
  # contacto (dato cruzado/typo en el Excel) -- se reintenta sin telefono
  # principal en vez de perder el contacto completo.
  if contact.errors.of_kind?(:phone_number, :taken)
    contact.phone_number = nil
    return contact if contact.save
  end
  nil
end

# Produccion puede estar en un deploy mas atrasado que este branch (ej.
# sin la migracion de amount_to_collect, agregada mas tarde en esta misma
# sesion) -- en vez de asumir que el schema coincide, se detecta y se
# omite ese campo (no es parte del objetivo de esta fase: corregir
# created_at/estado) en vez de tronar a mitad de la corrida.
HAS_AMOUNT_TO_COLLECT = Calendario::Appointment.column_names.include?('amount_to_collect')

account = Account.find(ACCOUNT_ID)
puts "== Fase 3 batch 4 -- cuenta ##{account.id} (#{account.name}) =="
puts '** AVISO: columna amount_to_collect no existe en este ambiente, se omite ese campo **' unless HAS_AMOUNT_TO_COLLECT
puts(APPLY ? '** APPLY=1: esto SI persiste cambios reales **' : '** DRY_RUN (default): se hace ROLLBACK al final, nada queda guardado **')

rows = SOURCE_FILES.flat_map do |fname|
  CSV.foreach(IMPORT_DIR.join(fname), headers: true, encoding: 'bom|utf-8').map { |r| r.to_h.merge('fuente_csv' => fname) }
end
puts "Filas leidas de los 3 CSV: #{rows.size}"

corrected = []
created = []
ambiguous = []
contact_not_found = []
service_unmapped = Hash.new(0)
payer_unmapped = Hash.new(0)
professionals_created = []
services_created = []
contacts_created = []

ActiveRecord::Base.transaction do
  specialties = {
    urologia: account.calendario_specialties.find_or_create_by!(name: 'Urología'),
    ginecologia: account.calendario_specialties.find_or_create_by!(name: 'Ginecología'),
  }
  known_payer_names = account.calendario_payers.pluck(:name).index_by { |n| normalize(n) }
  contacts_by_phone = {}
  account.contacts.where.not(phone_number: nil).find_each { |c| contacts_by_phone[c.phone_number] = c }
  account.contacts.where.not(secondary_phone_number: nil).find_each { |c| contacts_by_phone[c.secondary_phone_number] ||= c }
  contacts_by_doc = {}
  account.contacts.where.not(identifier: nil).find_each { |c| contacts_by_doc[c.identifier] = c }

  existing_professional_names = account.calendario_professionals.pluck(:name)
  existing_service_names = account.calendario_services.pluck(:name)

  rows.each do |row|
    next if row['cita_fecha_hora'].blank?

    professional = ensure_professional(account, specialties, row['profesional'])
    professionals_created << professional.name if professionals_created.exclude?(professional.name) && existing_professional_names.exclude?(professional.name)

    service_name = resolve_service_name(row['procedimiento'])
    if service_name.nil?
      service_unmapped[normalize(row['procedimiento'])] += 1
      next
    end
    service = ensure_service(account, service_name)
    services_created << service.name if services_created.exclude?(service.name) && existing_service_names.exclude?(service.name)
    ensure_service_professional_link(service, professional)

    contact = find_contact_by_phone(contacts_by_phone, row) || contacts_by_doc[row['cedula']]
    # Confirmado con el usuario 2026-11-25: tambien se crea sin telefono
    # (solo cedula+nombre) cuando el Excel no trae ningun telefono -- no
    # podra recibir WhatsApp hasta que alguien le agregue el numero despues.
    if contact.nil? && row['cedula'].present?
      contact = create_contact_from_row(account, row, known_payer_names)
      if contact
        contacts_created << contact
        contacts_by_doc[row['cedula']] = contact
        contacts_by_phone[contact.phone_number] = contact if contact.phone_number
        contacts_by_phone[contact.secondary_phone_number] = contact if contact.secondary_phone_number
      end
    end
    if contact.nil?
      contact_not_found << "#{row['nombre']} (#{row['telefono_principal']}) -- #{row['fuente_csv']}:#{row['fuente_bloque_titulo']}"
      next
    end

    payer_name = resolve_payer_name(row['entidad'], known_payer_names)
    payer_unmapped[normalize(row['entidad'])] += 1 if payer_name.nil? && normalize(row['entidad']).present? && normalize(row['entidad']) != 'CONSULTA'

    starts_at = Time.zone.parse(row['cita_fecha_hora'])
    same_day_matches = Calendario::Appointment.where(
      account_id: account.id, contact_id: contact.id, professional_id: professional.id,
      starts_at: starts_at.all_day
    )
    status = { 'atendida' => :attended, 'no_show' => :no_show, 'pendiente' => :pending }[row['estado']]
    amount = row['valor_cobrado'].presence&.to_i

    case same_day_matches.count
    when 0
      attrs = {
        account: account, contact: contact, professional: professional, service: service,
        starts_at: starts_at, historical_import: true,
        notes: "Importado fase 3 batch 4 -- #{row['fuente_csv']}:#{row['fuente_bloque_titulo']}",
      }
      attrs[:status] = status if status
      attrs[:amount_to_collect] = amount if amount && HAS_AMOUNT_TO_COLLECT
      attrs[:created_at] = BOGOTA.parse(row['solicitud_fecha_real']) if row['solicitud_fecha_real'].present?
      appointment = Calendario::Appointment.new(attrs)
      if appointment.save
        created << "#{contact.name} #{starts_at.to_date} #{service.name} (#{professional.name})"
        Calendario::OpenDayCoverage.new(account: account, professional_id: professional.id, starts_at: starts_at).ensure!
      else
        contact_not_found << "ERROR creando #{contact.name} #{starts_at}: #{appointment.errors.full_messages.join(', ')}"
      end
    when 1
      appointment = same_day_matches.first
      changes = {}
      if row['solicitud_fecha_real'].present?
        real_created_at = BOGOTA.parse(row['solicitud_fecha_real'])
        changes[:created_at] = real_created_at if appointment.created_at.to_date != real_created_at.to_date
      end
      changes[:status] = status if status && appointment.status.to_sym != status
      changes[:amount_to_collect] = amount if amount && HAS_AMOUNT_TO_COLLECT && appointment.amount_to_collect != amount
      if changes.any?
        appointment.update_columns(changes) if APPLY # update_columns: sin callbacks (no re-disparar triggers sobre una cita ya existente)
        corrected << "#{contact.name} #{starts_at.to_date} #{service.name}: #{changes.keys.join(',')}"
      end
    else
      ambiguous << "#{contact.name} (tel #{row['telefono_principal']}) #{starts_at.to_date} prof=#{professional.name} -- #{same_day_matches.count} citas existentes ese dia, no se toco ninguna"
    end
  end

  raise ActiveRecord::Rollback unless APPLY
end

report_path = IMPORT_DIR.join(APPLY ? 'phase3_apply_report.txt' : 'phase3_dry_run_report.txt')
File.open(report_path, 'w') do |f|
  f.puts "Fase 3 batch 4 -- #{Time.current} -- #{APPLY ? 'APPLY' : 'DRY_RUN'}"
  f.puts "Filas leidas: #{rows.size}"
  f.puts "Citas corregidas: #{corrected.size}"
  f.puts "Citas creadas: #{created.size}"
  f.puts "Ambiguas (2+ citas el mismo dia, no tocadas): #{ambiguous.size}"
  f.puts "Contacto no encontrado por telefono: #{contact_not_found.size}"
  f.puts "Contactos nuevos creados (telefono sin match previo): #{contacts_created.size}"
  f.puts "Profesionales nuevos: #{professionals_created.join(', ')}"
  f.puts "Servicios nuevos: #{services_created.join(', ')}"
  f.puts
  f.puts "== Procedimientos SIN mapear (#{service_unmapped.values.sum} filas, #{service_unmapped.size} variantes) =="
  service_unmapped.sort_by { |_, v| -v }.each { |k, v| f.puts "  #{v}\t#{k}" }
  f.puts
  f.puts "== Entidades SIN mapear a payer (#{payer_unmapped.values.sum} filas, #{payer_unmapped.size} variantes) =="
  payer_unmapped.sort_by { |_, v| -v }.each { |k, v| f.puts "  #{v}\t#{k}" }
  f.puts
  f.puts "== Ambiguas (#{ambiguous.size}) =="
  ambiguous.each { |l| f.puts "  #{l}" }
  f.puts
  f.puts "== Contacto no encontrado (#{contact_not_found.size}) =="
  contact_not_found.first(200).each { |l| f.puts "  #{l}" }
  f.puts "  ... (#{contact_not_found.size - 200} mas)" if contact_not_found.size > 200
end

puts
puts '== Resumen =='
puts "Citas corregidas: #{corrected.size}"
puts "Citas creadas: #{created.size}"
puts "Ambiguas sin tocar: #{ambiguous.size}"
puts "Contacto no encontrado: #{contact_not_found.size}"
puts "Contactos nuevos creados: #{contacts_created.size}"
puts "Procedimientos sin mapear: #{service_unmapped.values.sum} filas (#{service_unmapped.size} variantes)"
puts "Entidades sin mapear: #{payer_unmapped.values.sum} filas (#{payer_unmapped.size} variantes)"
puts "Profesionales nuevos: #{professionals_created.join(', ')}"
puts "Servicios nuevos: #{services_created.join(', ')}"
puts "Reporte completo: #{report_path}"

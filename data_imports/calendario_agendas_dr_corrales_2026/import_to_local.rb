# Carga local de "AGENDAS DR CORRALES 2026.xlsx" ya normalizado (ver
# normalize.py / prepare_import.py en esta misma carpeta) -- pensado para
# correrse tal cual el dia que se haga la migracion real a produccion, por
# eso es deliberadamente explicito y cauteloso: nunca inventa datos, nunca
# toca otra cuenta, y borra solo lo que el usuario autorizo borrar
# (Calendario + Contactos de ESTA cuenta, nada mas).
#
# Uso:
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/import_to_local.rb
#
# Variables de entorno opcionales:
#   ACCOUNT_ID=1   (cuenta destino, default 1)
#   SKIP_WIPE=1    (no borra nada -- solo agrega; util para reintentar tras un error)
#   DRY_RUN=1      (corre todo dentro de una transaccion y hace ROLLBACK al
#                   final -- nunca borra ni persiste nada real. Para validar
#                   que no hay errores de datos/Ruby antes de la corrida real.
#                   El borrado del paso 1 SI corre en DRY_RUN -- vive dentro
#                   de la misma transaccion que se revierte al final, asi que
#                   es tan seguro como el resto; si no corriera, una cuenta
#                   que YA tiene una carga anterior real (ej. fase 1) chocaria
#                   con "Identifier has already been taken" en cada contacto
#                   repetido y el dry-run no reflejaria el resultado real.)
#
# Requiere haber corrido antes: python3 normalize.py && python3 prepare_import.py

raise 'Este importador es solo para development -- revisar antes de usarlo en otro ambiente' unless Rails.env.development?

require 'csv'

IMPORT_DIR = Pathname.new(__dir__)
ACCOUNT_ID = (ENV['ACCOUNT_ID'] || 1).to_i
DRY_RUN = ENV['DRY_RUN'] == '1'
SKIP_WIPE = ENV['SKIP_WIPE'] == '1'

# Nombre -> especialidad ("urologia"/"ginecologia", resuelta mas abajo contra
# las especialidades reales de la cuenta). Maria y Dra. Cano son fase 2: ver
# CONTEXTO_NEGOCIO_FASE2.md -- Maria hace Urodinamia/Uroflujometria (agente
# tecnica, no doctora, pero el modelo no distingue eso); Dra. Cano = "Lida"
# (confirmado por HORAS MEDICO APOYO/CLAVES: "DRA LIDA MARIA CANO SALAZAR"),
# ginecologa, consultas particulares.
PROFESSIONALS_TO_ENSURE = {
  'Dr. Corrales' => :urologia, 'Dr. Devia' => :urologia, 'Dr. Velez' => :urologia,
  'Dr. Gaviria' => :urologia, 'Dra. España' => :urologia, 'Dr. Heredia' => :urologia,
  'María' => :urologia, 'Dra. Cano' => :ginecologia,
}.freeze

# Duraciones por defecto RAZONABLES pero NO confirmadas por la clinica --
# quedan marcadas en el reporte final para que el equipo las ajuste en la
# pestaña Servicios despues de revisar. El color SI es solo visual (no una
# decision de negocio) -- se le pone uno igual para que el calendario/vista
# por profesional nunca muestre un servicio sin color (pedido explicito del
# usuario: "todos los servicios deben de tener un color").
SERVICE_DEFAULTS = {
  'Urocultivo' => { duration_minutes: 15, kind: :procedure, color: '#D9D9D9' },
  'Biopsia de prostata' => { duration_minutes: 30, kind: :procedure, color: '#4BACC6' },
  'Post quirurgico' => { duration_minutes: 15, kind: :control, color: '#76923C' },
  'Retiro de cateter' => { duration_minutes: 15, kind: :procedure, color: '#D99694' },
  'Uroflujometria' => { duration_minutes: 15, kind: :procedure, color: '#FFC000' },
  # Nuevos en la ronda de auditoria 2026-11-17 -- servicios reales que antes
  # caian en "Otro" y por eso nunca se importaban (ver CONTEXTO_NEGOCIO_FASE2.md).
  'Colposcopia' => { duration_minutes: 20, kind: :procedure, color: '#C4BD97' },
  'Litotricia' => { duration_minutes: 45, kind: :procedure, color: '#948A54' },
  'Pesario' => { duration_minutes: 15, kind: :procedure, color: '#E6B9B8' },
  'Sexologia' => { duration_minutes: 30, kind: :consultation, color: '#B2A2C7' },
  'Cauterizacion' => { duration_minutes: 20, kind: :procedure, color: '#C0504D' },
  'Conizacion' => { duration_minutes: 30, kind: :procedure, color: '#92CDDC' },
}.freeze

PAYER_KIND_HINTS = {
  'PARTICULAR' => :particular,
  'SURA POLIZA' => :poliza,
}.freeze

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

def payer_kind_for(name)
  return PAYER_KIND_HINTS[name] if PAYER_KIND_HINTS.key?(name)
  return :poliza if name.include?('POLIZA')
  return :prepagada if name.include?('PREPAGADA')

  :eps
end

def ensure_payer(account, raw_name)
  return nil if raw_name.blank?

  name = raw_name.strip.split.map(&:capitalize).join(' ')
  account.calendario_payers.find_by('lower(name) = ?', name.downcase) ||
    account.calendario_payers.create!(name: name, kind: payer_kind_for(raw_name))
end

account = Account.find(ACCOUNT_ID)
puts "== Importando a la cuenta ##{account.id} (#{account.name}) =="
puts '** DRY_RUN: no se guardara nada, se hace rollback al final **' if DRY_RUN

contacts_by_doc = {}
contact_errors = []
appointment_count = 0
appointment_errors = []
appointments_by_doc_prof = Hash.new { |h, k| h[k] = [] }
waitlist_count = 0
waitlist_fulfilled_count = 0
waitlist_errors = []

# Todo lo que sigue corre dentro de UNA transaccion -- en DRY_RUN se hace
# rollback al final, lo que permite correr el importador completo contra la
# base real para detectar errores de datos/Ruby sin arriesgar nada.
ActiveRecord::Base.transaction do
  specialties = {
    urologia: account.calendario_specialties.find_or_create_by!(name: 'Urología'),
    ginecologia: account.calendario_specialties.find_or_create_by!(name: 'Ginecología'),
  }

  # --- Paso 1: borrar SOLO datos de Calendario + Contactos de esta cuenta --
  # No se toca: usuarios, agentes, profesionales/servicios/EPS/especialidades
  # ya configurados (son configuracion del consultorio, se reusan), ni
  # ninguna otra cuenta.
  unless SKIP_WIPE
    puts '-- Borrando datos previos de Calendario y Contactos de esta cuenta --'
    Calendario::AppointmentAuditLog.where(account_id: account.id).delete_all
    Calendario::ContactSessionCredit.where(account_id: account.id).delete_all
    Calendario::Appointment.where(account_id: account.id).delete_all
    Calendario::WaitlistEntry.where(account_id: account.id).delete_all
    Calendario::OpenDay.where(account_id: account.id).delete_all
    account.contacts.find_each(&:destroy!)
    puts "   listo (#{account.contacts.count} contactos restantes, deberia ser 0)"
  end

  # --- Paso 2: profesionales mencionados en el Excel que no existen aun ---
  # "Dr. Heredia" aparece en el Consultorio 2 de varios lunes de la hoja
  # "DR CORRALES" pero no tiene registro propio en el sistema -- se crea sin
  # agente vinculado (igual que cualquier profesional sin acceso a Chatwoot).
  # Ver README.md, "Hallazgo 2".
  professionals_by_name = PROFESSIONALS_TO_ENSURE.each_with_object({}) do |(name, specialty_key), memo|
    professional = account.calendario_professionals.find_or_create_by!(name: name) do |p|
      p.specialty = specialties.fetch(specialty_key)
    end
    # Auditoria 2026-11-17: Dr. Devia y Dra. España ya existian (creados en
    # una sesion anterior) marcados active:false, asi que find_or_create_by!
    # los encontraba y los reusaba TAL CUAL -- sus citas reales quedaban
    # invisibles en Agendas/filtros (un profesional archivado no aparece ahi,
    # ver CalendarioSchedulesPage.vue). Todos los profesionales de este Excel
    # estan en operacion real, nunca deberian quedar archivados por esto.
    professional.update!(active: true) unless professional.active
    memo[name] = professional
  end

  # --- Paso 3: Contactos --------------------------------------------------
  puts '-- Cargando contactos --'
  CSV.foreach(IMPORT_DIR.join('contacts.csv'), headers: true, encoding: 'bom|utf-8') do |row|
    payer = ensure_payer(account, row['entidad_eps'])
    contact = account.contacts.new(
      name: row['nombre'].strip,
      identifier: row['numero_documento'],
      document_type: row['tipo_documento'].presence || 'cc',
      phone_number: row['telefono_1'].present? ? "+57#{row['telefono_1']}" : nil,
      secondary_phone_number: row['telefono_2'].present? ? "+57#{row['telefono_2']}" : nil,
      payer: payer
    )
    if contact.save
      contacts_by_doc[row['numero_documento']] = contact
    elsif contact.errors.of_kind?(:phone_number, :taken) && contact.tap { |c| c.phone_number = nil }.save
      # Caso mas comun: telefono_1 ya usado por otro contacto (typo de
      # digitacion en el Excel que hizo que dos pacientes distintos
      # quedaran con el mismo numero) -- se reintenta sin telefono en vez de
      # perder el contacto completo, y se deja constancia en el reporte.
      contacts_by_doc[row['numero_documento']] = contact
      contact_errors << "#{row['numero_documento']} #{row['nombre']}: telefono principal duplicado con otro contacto, se guardo sin telefono principal"
    else
      contact_errors << "#{row['numero_documento']} #{row['nombre']}: #{contact.errors.full_messages.join(', ')}"
    end
  end
  puts "   #{contacts_by_doc.size} contactos creados, #{contact_errors.size} con error"

  # --- Paso 4: Citas --------------------------------------------------------
  puts '-- Cargando citas --'
  CSV.foreach(IMPORT_DIR.join('appointments.csv'), headers: true, encoding: 'bom|utf-8') do |row|
    contact = contacts_by_doc[row['numero_documento']]
    if contact.nil?
      appointment_errors << "fila #{row['fuente_hoja']}:#{row['fuente_fila']} -- contacto #{row['numero_documento']} no se pudo crear, cita omitida"
      next
    end

    professional = professionals_by_name.fetch(row['profesional'])
    service = ensure_service(account, row['servicio_normalizado'])
    ensure_service_professional_link(service, professional)

    # El Excel registra hora LOCAL del consultorio (America/Bogota) -- usar
    # Time.zone.parse (UTC en este servidor) desplazaria todo 5 horas. Mismo
    # criterio que Calendario::OpenDayCoverage / calendarioDateTime.js.
    bogota_zone = ActiveSupport::TimeZone['America/Bogota']
    starts_at = bogota_zone.parse("#{row['fecha_programada']} #{row['hora_programada']}")
    notes = row['notas']
    notes = "[HORA ESTIMADA, no estaba en el Excel original] #{notes}" if row['hora_es_estimada'] == 'si'
    # Color de fila en el Excel real (ver normalize.py#attendance_from_fill,
    # confirmado por el usuario 2026-11-16 fila por fila) -- "revisar_color"
    # u otro valor no reconocido se deja en pending (default del modelo) en
    # vez de adivinar. Se fija como atributo en el CREATE (no con
    # mark_attended!/mark_no_show! despues) para que los callbacks de
    # cambio de ESTADO (que no tienen guarda de historical_import, ver
    # Calendario::Appointment#run_on_status_change_triggers) nunca corran
    # sobre una carga historica -- un create nunca dispara "saved_change_to_status?".
    status = { 'attended' => :attended, 'no_show' => :no_show }[row['asistencia']]

    attrs = {
      account: account, contact: contact, professional: professional, service: service,
      starts_at: starts_at, notes: notes, historical_import: true
    }
    # Ojo: NO pasar `status: nil` cuando no hay color reconocido -- el
    # setter de enum lo asignaria explicitamente en vez de dejar que la
    # columna use su default (`pending`, NOT NULL), y el insert fallaria.
    attrs[:status] = status if status
    appointment = Calendario::Appointment.new(attrs)
    if appointment.save
      appointment_count += 1
      # La pestaña "Agendas" se organiza por Calendario::OpenDay ("agenda
      # abierta"), no directamente por cita -- sin este paso, las citas
      # importadas existen en la base pero son invisibles en esa vista.
      Calendario::OpenDayCoverage.new(account: account, professional_id: professional.id, starts_at: starts_at).ensure!
      # Para el Paso 6 (lista de espera "cumplida"): poder encontrar, dado
      # un documento+profesional+fecha real, QUE cita se creo -- asi se
      # puede enlazar fulfilled_by_appointment_id en vez de solo guardar la
      # fecha como texto.
      appointments_by_doc_prof[[row['numero_documento'], row['profesional']]] << appointment
    else
      appointment_errors << "fila #{row['fuente_hoja']}:#{row['fuente_fila']} (#{row['numero_documento']}): #{appointment.errors.full_messages.join(', ')}"
    end
  end
  puts "   #{appointment_count} citas creadas, #{appointment_errors.size} con error"

  # --- Paso 5: Lista de espera ---------------------------------------------
  puts '-- Cargando lista de espera --'
  CSV.foreach(IMPORT_DIR.join('waitlist.csv'), headers: true, encoding: 'bom|utf-8') do |row|
    contact = contacts_by_doc[row['numero_documento']]
    if contact.nil?
      waitlist_errors << "fila #{row['fuente_hoja']}:#{row['fuente_fila']} -- contacto #{row['numero_documento']} no se pudo crear, entrada omitida"
      next
    end

    professional = professionals_by_name.fetch(row['profesional'])
    service = ensure_service(account, row['servicio_normalizado'])
    ensure_service_professional_link(service, professional)

    entry_attrs = {
      contact: contact, professional: professional, service: service, notes: row['notas']
    }
    # created_at REAL (cuando se registro el paciente pidiendo cupo, columna
    # "FECHA" del Excel) -- confirmado por el usuario 2026-11-17: sin esto,
    # todas las entradas historicas quedaban con el mismo created_at (el
    # instante de esta carga), asi que "dias esperando" y el orden "mas
    # antiguas primero" no tenian ningun sentido real. Si no hay fecha de
    # solicitud en el Excel, se deja que Rails use el default (ahora).
    if row['fecha_solicitud'].present?
      entry_attrs[:created_at] = ActiveSupport::TimeZone['America/Bogota'].parse(row['fecha_solicitud'])
    end
    entry = account.calendario_waitlist_entries.new(entry_attrs)
    if entry.save
      waitlist_count += 1
    else
      waitlist_errors << "fila #{row['fuente_hoja']}:#{row['fuente_fila']} (#{row['numero_documento']}): #{entry.errors.full_messages.join(', ')}"
    end
  end
  puts "   #{waitlist_count} entradas de lista de espera creadas, #{waitlist_errors.size} con error"

  # --- Paso 6: Lista de espera "cumplida" ----------------------------------
  # Pedido explicito del usuario 2026-11-17: gente que aparecia en una hoja
  # de lista de espera pero YA tenia una cita real en otra hoja -- no sigue
  # esperando, pero su fecha de solicitud y la cita que la resolvio importan
  # para la estadistica de "cuanto tiempo se tardo". Se crea con
  # status: :fulfilled y enlazada via fulfilled_by_appointment_id a la cita
  # real mas antigua que se le encontro (ver appointments_by_doc_prof,
  # llenado en el Paso 4).
  puts '-- Cargando lista de espera cumplida --'
  CSV.foreach(IMPORT_DIR.join('waitlist_fulfilled.csv'), headers: true, encoding: 'bom|utf-8') do |row|
    contact = contacts_by_doc[row['numero_documento']]
    if contact.nil?
      waitlist_errors << "fila #{row['fuente_hoja']}:#{row['fuente_fila']} -- contacto #{row['numero_documento']} no se pudo crear, entrada cumplida omitida"
      next
    end

    professional = professionals_by_name.fetch(row['profesional'])
    service = ensure_service(account, row['servicio_normalizado'])
    ensure_service_professional_link(service, professional)

    # prepare_import.py ya eligio la fecha correcta en 'fecha_cita_real'
    # (la primera cita real EN O DESPUES de la fecha de solicitud -- una
    # cita anterior es una visita vieja sin relacion, ver build_schedule_rows).
    # Aqui solo se busca el objeto Appointment que quedo en esa fecha.
    candidates = appointments_by_doc_prof[[row['numero_documento'], row['profesional']]]
    fulfilled_by = candidates.find { |ap| ap.starts_at.to_date.iso8601 == row['fecha_cita_real'] } || candidates.min_by(&:starts_at)

    entry_attrs = {
      contact: contact, professional: professional, service: service, notes: row['notas'],
      status: :fulfilled, fulfilled_by_appointment: fulfilled_by,
    }
    # Sin fecha_solicitud en el Excel no hay como calcular cuanto espero
    # (ver prepare_import.py) -- se usa la fecha de la cita real como
    # created_at (dias de espera = 0/desconocido) en vez de dejar el
    # default de Rails (el instante de esta carga), que comparado contra
    # una cita real de hace meses daba numeros negativos sin sentido.
    fecha_created = row['fecha_solicitud'].presence || row['fecha_cita_real']
    entry_attrs[:created_at] = ActiveSupport::TimeZone['America/Bogota'].parse(fecha_created) if fecha_created.present?
    entry = account.calendario_waitlist_entries.new(entry_attrs)
    if entry.save
      waitlist_fulfilled_count += 1
    else
      waitlist_errors << "fila #{row['fuente_hoja']}:#{row['fuente_fila']} (#{row['numero_documento']}) [cumplida]: #{entry.errors.full_messages.join(', ')}"
    end
  end
  puts "   #{waitlist_fulfilled_count} entradas de lista de espera cumplida creadas"

  raise ActiveRecord::Rollback if DRY_RUN
end

# --- Reporte final -----------------------------------------------------------
report_path = IMPORT_DIR.join(DRY_RUN ? 'dry_run_report.txt' : 'import_report.txt')
account.reload unless DRY_RUN
File.open(report_path, 'w') do |f|
  f.puts "Importe local -- #{Time.current}"
  f.puts "Cuenta: #{account.id} (#{account.name})"
  f.puts
  f.puts "Contactos creados: #{contacts_by_doc.size}"
  f.puts "Citas creadas: #{appointment_count}"
  f.puts "Lista de espera creada (pendiente): #{waitlist_count}"
  f.puts "Lista de espera creada (cumplida, ya tenia cita): #{waitlist_fulfilled_count}"
  f.puts
  f.puts 'Servicios nuevos creados con duracion por defecto (confirmar con la clinica):'
  SERVICE_DEFAULTS.each_key { |name| f.puts "  - #{name}" if account.calendario_services.exists?(name: name) }
  f.puts
  f.puts 'Profesionales nuevos creados (confirmar si corresponde o reasignar):'
  %w[Dr.\ Heredia María Dra.\ Cano].each do |name|
    f.puts "  - #{name}" if account.calendario_professionals.exists?(name: name)
  end
  f.puts
  f.puts "== Errores de contactos (#{contact_errors.size}) =="
  contact_errors.each { |e| f.puts "  #{e}" }
  f.puts
  f.puts "== Errores de citas (#{appointment_errors.size}) =="
  appointment_errors.each { |e| f.puts "  #{e}" }
  f.puts
  f.puts "== Errores de lista de espera (#{waitlist_errors.size}) =="
  waitlist_errors.each { |e| f.puts "  #{e}" }
end

puts
puts '== Resumen =='
puts "Contactos: #{contacts_by_doc.size}"
puts "Citas: #{appointment_count}"
puts "Lista de espera pendiente: #{waitlist_count}"
puts "Lista de espera cumplida: #{waitlist_fulfilled_count}"
puts "Errores totales: #{contact_errors.size + appointment_errors.size + waitlist_errors.size}"
puts(DRY_RUN ? '(DRY_RUN -- nada de esto quedo guardado)' : "Reporte completo: #{report_path}")
puts
pendientes_count = File.read(IMPORT_DIR.join('pendientes_sin_profesional.csv')).lines.count - 1
puts "Recordatorio: #{pendientes_count} filas del Excel quedaron SIN IMPORTAR"
puts '(sin profesional resuelto en el archivo original) -- ver pendientes_sin_profesional.csv'

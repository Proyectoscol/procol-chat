# Fase 1 del plan de migración a producción (ver /Users/camilocastillo/.claude/plans/validated-forging-piglet.md):
# script de SOLO LECTURA, no modifica nada. Corre con:
#   bundle exec rails runner data_imports/calendario_agendas_dr_corrales_2026/verify_data_integrity.rb
ACCOUNT_ID = (ENV['ACCOUNT_ID'] || 1).to_i
account = Account.find(ACCOUNT_ID)

puts "== Verificación de integridad -- cuenta ##{account.id} (#{account.name}) =="
puts

# --- 1. Contactos duplicados por teléfono ---
puts '-- 1. Contactos duplicados por teléfono --'
dupe_phones = Contact.where(account_id: account.id)
                     .where.not(phone_number: [nil, ''])
                     .group(:phone_number)
                     .having('COUNT(*) > 1')
                     .count
if dupe_phones.empty?
  puts '  Ninguno encontrado.'
else
  puts "  #{dupe_phones.size} números con más de un contacto:"
  dupe_phones.each do |phone, count|
    contacts = Contact.where(account_id: account.id, phone_number: phone)
    puts "    #{phone} (#{count} contactos): #{contacts.map { |c| "id=#{c.id} name=#{c.name.inspect}" }.join(', ')}"
  end
end
puts

# --- 2. Citas cuyo contact_id no coincide con el contact_id de su conversación ---
puts '-- 2. Citas con conversación asociada pero contacto distinto --'
mismatched = Calendario::Appointment.where(account_id: account.id).where.not(conversation_id: nil).includes(:conversation).select do |a|
  a.conversation.present? && a.conversation.contact_id != a.contact_id
end
if mismatched.empty?
  puts '  Ninguna encontrada.'
else
  puts "  #{mismatched.size} citas con contacto distinto al de su conversación:"
  mismatched.each do |a|
    puts "    appointment_id=#{a.id} appointment.contact_id=#{a.contact_id} conversation_id=#{a.conversation_id} conversation.contact_id=#{a.conversation.contact_id}"
  end
end
puts

# --- 3. Conversaciones con/sin citas (informativo) ---
puts '-- 3. Conversaciones con y sin citas asociadas (informativo) --'
total_conversations = Conversation.where(account_id: account.id).count
contact_ids_with_appointments = Calendario::Appointment.where(account_id: account.id).distinct.pluck(:contact_id)
conversations_with_appt_contact = Conversation.where(account_id: account.id, contact_id: contact_ids_with_appointments).count
puts "  Total conversaciones: #{total_conversations}"
puts "  Conversaciones cuyo contacto SÍ tiene al menos una cita: #{conversations_with_appt_contact}"
puts "  Conversaciones cuyo contacto NO tiene ninguna cita (normal para quien solo escribió, nunca agendó): #{total_conversations - conversations_with_appt_contact}"
puts

# --- 4. Adjuntos cuyo blob no existe en disco ---
puts '-- 4. Adjuntos con blob roto (no existe en el storage) --'
broken_attachments = []
Attachment.joins(:message).where(messages: { account_id: account.id }).find_each do |a|
  next unless a.file.attached?

  begin
    exists = a.file.blob.service.exist?(a.file.blob.key)
    broken_attachments << a unless exists
  rescue StandardError => e
    broken_attachments << a
    puts "    (error verificando attachment id=#{a.id}: #{e.message})"
  end
end
if broken_attachments.empty?
  puts '  Ninguno encontrado (todos los blobs existen en disco).'
else
  puts "  #{broken_attachments.size} adjuntos con blob roto:"
  broken_attachments.first(20).each { |a| puts "    attachment_id=#{a.id} message_id=#{a.message_id} filename=#{a.file.filename rescue '?'}" }
end
puts

# --- 5. Citas/lista de espera huérfanas (profesional o servicio inactivo/borrado) ---
puts '-- 5. Citas con profesional o servicio inactivo --'
inactive_prof_appts = Calendario::Appointment.where(account_id: account.id).joins(:professional).where(calendario_professionals: { active: false }).count
puts "  Citas con profesional inactivo: #{inactive_prof_appts}"

puts '-- 5b. Lista de espera con profesional o servicio inactivo --'
inactive_prof_waitlist = Calendario::WaitlistEntry.where(account_id: account.id).joins(:professional).where(calendario_professionals: { active: false }).count
puts "  Entradas de lista de espera con profesional inactivo: #{inactive_prof_waitlist}"
puts

# --- 6. Resumen de conteos ---
puts '-- 6. Resumen de conteos (para comparar luego contra el manifest del export) --'
puts "  Especialidades: #{Calendario::Specialty.where(account_id: account.id).count}"
puts "  EPS/pagadores: #{Calendario::Payer.where(account_id: account.id).count}"
puts "  Profesionales: #{Calendario::Professional.where(account_id: account.id).count}"
puts "  Servicios: #{Calendario::Service.where(account_id: account.id).count}"
puts "  Contactos: #{Contact.where(account_id: account.id).count}"
puts "  Conversaciones: #{Conversation.where(account_id: account.id).count}"
puts "  Mensajes: #{Message.where(account_id: account.id).count}"
puts "  Adjuntos: #{Attachment.joins(:message).where(messages: { account_id: account.id }).count}"
puts "  Citas: #{Calendario::Appointment.where(account_id: account.id).count}"
puts "  Lista de espera (pendiente): #{Calendario::WaitlistEntry.where(account_id: account.id, status: :pending).count}"
puts "  Lista de espera (cumplida): #{Calendario::WaitlistEntry.where(account_id: account.id, status: :fulfilled).count}"
puts "  Lista de espera (cancelada): #{Calendario::WaitlistEntry.where(account_id: account.id, status: :cancelled).count}"
puts "  Agendas abiertas (OpenDay): #{Calendario::OpenDay.where(account_id: account.id).count}"

puts
puts '== Fin de la verificación -- nada fue modificado =='

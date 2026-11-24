# Importa un .zip generado por Calendario::AccountDataExportService dentro
# de ESTA cuenta -- siempre aditivo (nunca borra ni pisa nada existente),
# siempre dentro de una transaccion (si algo falla a mitad de camino, se
# revierte todo). Ver Calendario::AccountDataTransferSpec para el detalle
# exacto de modelos/orden/FKs.
class Calendario::AccountDataImportService
  include Calendario::AccountDataTransferSpec

  pattr_initialize [:import!]

  def perform
    import.update!(status: :processing)
    account = import.account
    target_inbox = import.inbox

    stats = {}
    Dir.mktmpdir do |dir|
      extract_zip(dir)
      data = JSON.parse(File.read(File.join(dir, 'data.json')))
      manifest = JSON.parse(File.read(File.join(dir, 'manifest.json')))
      raise "Formato de export no soportado (version #{manifest['format_version']})" unless manifest['format_version'] == FORMAT_VERSION

      @id_maps = Hash.new { |h, k| h[k] = {} }
      @attachments_dir = File.join(dir, 'attachments')

      ActiveRecord::Base.transaction do
        MODELS.each do |model_spec|
          stats[model_spec[:key]] = import_rows(model_spec, data.fetch(model_spec[:key], []), account, target_inbox)
        end
      end
    end

    import.update!(status: :completed, stats: stats)
  rescue StandardError => e
    import.update!(status: :failed, error_message: "#{e.class}: #{e.message}")
    raise
  end

  private

  def extract_zip(dir)
    require 'zip'
    import.import_file.blob.open do |tempfile|
      Zip::File.open(tempfile.path) do |zip_file|
        zip_file.each do |entry|
          next unless entry.file?

          entry.extract(entry.name, destination_directory: dir, create_parent_directories: true)
        end
      end
    end
  end

  def import_rows(model_spec, rows, account, target_inbox)
    key = model_spec[:key]
    stats = { created: 0, reused: 0, skipped: 0, errors: 0 }
    rows.each do |row|
      old_id = row['id']
      new_id = import_row(key, row, account, target_inbox, stats)
      @id_maps[key][old_id] = new_id if new_id
    rescue StandardError => e
      stats[:errors] += 1
      Rails.logger.error("[Calendario::AccountDataImportService] #{key} id=#{old_id} error: #{e.message}")
    end
    stats
  end

  def import_row(key, row, account, target_inbox, stats)
    case key
    when 'specialties', 'payers', 'services'
      find_or_create_by_name(key, row, account, stats)
    when 'professionals'
      import_professional(row, account, stats)
    when 'service_professionals', 'service_prices', 'professional_availabilities'
      import_detail_row(key, row, stats)
    when 'contacts'
      import_contact(row, account, stats)
    when 'contact_inboxes'
      import_contact_inbox(row, target_inbox, stats)
    when 'conversations'
      import_conversation(row, account, target_inbox, stats)
    when 'messages'
      import_message(row, account, target_inbox, stats)
    when 'attachments'
      import_attachment(row, stats)
    when 'open_days'
      import_open_day(row, account, stats)
    when 'appointments'
      import_appointment(row, account, stats)
    when 'appointment_audit_logs', 'waitlist_entries', 'contact_session_credits'
      import_simple(key, row, account, stats)
    end
  end

  # Specialty/Payer/Service: nombre unico por cuenta -- si ya existe uno
  # igual en destino (lo configuraron a mano o de un import anterior), se
  # reusa en vez de chocar con el indice unico.
  def find_or_create_by_name(key, row, account, stats)
    klass = Calendario::AccountDataTransferSpec.model_class_for(key)
    existing = klass.find_by(account_id: account.id, name: row['name'])
    if existing
      stats[:reused] += 1
      return existing.id
    end

    attrs = row.except('id', 'account_id', 'created_at', 'updated_at')
    record = klass.create!(attrs.merge(account_id: account.id))
    stats[:created] += 1
    record.id
  end

  def import_professional(row, account, stats)
    existing = Calendario::Professional.find_by(account_id: account.id, name: row['name'])
    if existing
      stats[:reused] += 1
      return existing.id
    end

    attrs = row.except('id', 'account_id', 'user_id', 'created_at', 'updated_at', 'specialty_id')
    attrs['specialty_id'] = remap('specialties', row['specialty_id'])
    record = Calendario::Professional.create!(attrs.merge(account_id: account.id))
    stats[:created] += 1
    record.id
  end

  def import_detail_row(key, row, stats)
    klass = Calendario::AccountDataTransferSpec.model_class_for(key)
    attrs = row.except('id', 'created_at', 'updated_at')
    apply_fk_remaps!(key, attrs)
    klass.create!(attrs)
    stats[:created] += 1
    nil
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    stats[:skipped] += 1
    nil
  end

  # Un mismo numero de telefono ya en la cuenta destino es la MISMA persona
  # -- se reusa su contacto (le cuelga historial nuevo) en vez de duplicarlo.
  def import_contact(row, account, stats)
    phone = row['phone_number']
    if phone.present?
      existing = Contact.find_by(account_id: account.id, phone_number: phone)
      if existing
        stats[:reused] += 1
        return existing.id
      end
    end

    attrs = row.except('id', 'account_id', 'created_at', 'updated_at', 'payer_id')
    attrs['payer_id'] = remap('payers', row['payer_id']) if row['payer_id']
    record = Contact.create!(attrs.merge(account_id: account.id))
    stats[:created] += 1
    record.id
  end

  # source_id se genera fresco para la bandeja de DESTINO -- el de origen
  # (excluido del export) era especifico de la bandeja vieja. Mismo patron
  # que Import::WhatsappChatImportService: telefono real -> "whatsapp:+E164"
  # (Twilio) o digitos sueltos (Meta); username guardado en additional_attributes
  # (ver Calendario::ReturningAppointmentPromptListener/Whatsapp::IdentifierSyncService)
  # -> "whatsapp:@username".
  def import_contact_inbox(row, target_inbox, stats)
    contact_id = remap('contacts', row['contact_id'])
    unless contact_id
      stats[:skipped] += 1
      return nil
    end

    contact = Contact.find(contact_id)
    source_id = source_id_for(contact, target_inbox)
    if source_id.blank?
      stats[:skipped] += 1
      return nil
    end

    existing = target_inbox.contact_inboxes.find_by(source_id: source_id)
    if existing
      stats[:reused] += 1
      return existing.id
    end

    record = target_inbox.contact_inboxes.create!(contact_id: contact_id, source_id: source_id)
    stats[:created] += 1
    record.id
  end

  def source_id_for(contact, inbox)
    username = contact.additional_attributes['social_whatsapp_user_name']
    twilio_whatsapp = inbox.channel_type == 'Channel::TwilioSms' && inbox.channel.medium == 'whatsapp'

    if username.present?
      return twilio_whatsapp ? "whatsapp:@#{username}" : "@#{username}"
    end
    return if contact.phone_number.blank?

    digits = contact.phone_number.delete_prefix('+')
    twilio_whatsapp ? "whatsapp:+#{digits}" : digits
  end

  def import_conversation(row, account, target_inbox, stats)
    contact_id = remap('contacts', row['contact_id'])
    contact_inbox_id = remap('contact_inboxes', row['contact_inbox_id'])
    unless contact_id && contact_inbox_id
      stats[:skipped] += 1
      return nil
    end

    existing = Conversation.find_by(account_id: account.id, inbox_id: target_inbox.id, contact_id: contact_id)
    if existing
      stats[:reused] += 1
      return existing.id
    end

    attrs = row.except('id', 'account_id', 'inbox_id', 'contact_id', 'contact_inbox_id', 'created_at', 'updated_at')
    record = Conversation.create!(
      attrs.merge(account_id: account.id, inbox_id: target_inbox.id, contact_id: contact_id, contact_inbox_id: contact_inbox_id)
    )
    stats[:created] += 1
    record.id
  end

  # Capa de seguridad: igual que todo el import de WhatsApp de esta sesion,
  # TODO mensaje importado es privado y esta marcado como historico, sin
  # importar lo que diga el export -- nunca debe poder disparar un envio real.
  def import_message(row, account, target_inbox, stats)
    conversation_id = remap('conversations', row['conversation_id'])
    unless conversation_id
      stats[:skipped] += 1
      return nil
    end

    source_id = row['source_id']
    if source_id.present? && Message.exists?(conversation_id: conversation_id, source_id: source_id)
      stats[:skipped] += 1
      return nil
    end

    sender_type = row['sender_type']
    sender_id = sender_type == 'Contact' ? remap('contacts', row['sender_id']) : nil
    sender_type = nil if sender_id.blank?

    content_attributes = (row['content_attributes'] || {}).merge('historical_import' => true)

    attrs = row.except('id', 'account_id', 'inbox_id', 'conversation_id', 'sender_id', 'sender_type',
                       'content_attributes', 'private', 'created_at', 'updated_at')
    record = Message.create!(
      attrs.merge(
        account_id: account.id, inbox_id: target_inbox.id, conversation_id: conversation_id,
        sender_id: sender_id, sender_type: sender_type, private: true, content_attributes: content_attributes,
        created_at: row['created_at']
      )
    )
    stats[:created] += 1
    record.id
  end

  def import_attachment(row, stats)
    message_id = remap('messages', row['message_id'])
    unless message_id
      stats[:skipped] += 1
      return nil
    end

    file_path = Dir.glob(File.join(@attachments_dir, "#{row['id']}-*")).first
    unless file_path
      stats[:skipped] += 1
      return nil
    end

    attrs = row.except('id', 'message_id', 'created_at', 'updated_at')
    record = Attachment.new(attrs.merge(message_id: message_id, account_id: Message.find(message_id).account_id))
    record.file.attach(
      io: File.open(file_path), filename: File.basename(file_path).sub(/\A\d+-/, ''),
      content_type: Marcel::MimeType.for(Pathname.new(file_path))
    )
    record.save!
    stats[:created] += 1
    record.id
  end

  def import_open_day(row, account, stats)
    professional_id = remap('professionals', row['professional_id'])
    unless professional_id
      stats[:skipped] += 1
      return nil
    end

    if account.calendario_open_days.exists?(professional_id: professional_id, date: row['date'])
      stats[:reused] += 1
      return nil
    end

    attrs = row.except('id', 'account_id', 'professional_id', 'opened_by_id', 'created_at', 'updated_at')
    record = Calendario::OpenDay.create!(attrs.merge(account_id: account.id, professional_id: professional_id))
    stats[:created] += 1
    record.id
  end

  # historical_import: true (soportado nativamente por el modelo) salta
  # triggers, la validacion de "no en el pasado" y el chequeo de historial
  # previo de un control -- es exactamente la carga de citas que ya paso,
  # no una cita nueva de verdad.
  def import_appointment(row, account, stats)
    attrs = row.except('id', 'account_id', 'professional_id', 'service_id', 'contact_id', 'conversation_id',
                       'created_by_id', 'created_at', 'updated_at')
    professional_id = remap('professionals', row['professional_id'])
    service_id = remap('services', row['service_id'])
    contact_id = remap('contacts', row['contact_id'])
    unless professional_id && service_id && contact_id
      stats[:skipped] += 1
      return nil
    end

    conversation_id = row['conversation_id'] ? remap('conversations', row['conversation_id']) : nil
    record = Calendario::Appointment.new(
      attrs.merge(
        account_id: account.id, professional_id: professional_id, service_id: service_id,
        contact_id: contact_id, conversation_id: conversation_id, historical_import: true
      )
    )
    record.save!
    stats[:created] += 1
    record.id
  end

  def import_simple(key, row, account, stats)
    klass = Calendario::AccountDataTransferSpec.model_class_for(key)
    attrs = row.except('id', 'account_id', 'created_at', 'updated_at')
    apply_fk_remaps!(key, attrs)
    record = klass.create!(attrs.merge(account_id: account.id))
    stats[:created] += 1
    record.id
  end

  def apply_fk_remaps!(key, attrs)
    spec = MODELS.find { |m| m[:key] == key }
    spec[:fk_remaps].each do |column, target_key|
      next if attrs[column].blank?

      attrs[column] = remap(target_key, attrs[column])
    end
  end

  def remap(key, old_id)
    return nil if old_id.blank?

    @id_maps[key][old_id]
  end
end

# Corrige mensajes de WhatsApp (Twilio) que llegaron ANTES del fix de
# Twilio::IncomingMessageService#attach_vcard_contacts -- en ese momento el
# vcard crudo quedo guardado tal cual en content en vez de convertirse en
# una burbuja de contacto. Re-procesa ese texto con el mismo parser que ya
# usa el flujo en tiempo real, para que quede identico a como habria
# quedado si el fix ya hubiera estado desplegado.
#
# Uso: bundle exec rake auditoria:vcard_backfill
# Para una sola cuenta: ACCOUNT_ID=1 bundle exec rake auditoria:vcard_backfill
namespace :auditoria do
  desc 'Convierte vcards crudos guardados en content (antes del fix de Twilio) a burbuja de contacto'
  task vcard_backfill: :environment do
    # %...% (no solo al inicio): confirmado contra produccion que estos
    # mensajes de Twilio a veces traen algo antes de "BEGIN:VCARD" (un
    # salto de linea en blanco) -- un LIKE anclado al inicio los pierde.
    scope = Message.where("content LIKE '%BEGIN:VCARD%'")
    scope = scope.where(account_id: ENV['ACCOUNT_ID']) if ENV['ACCOUNT_ID'].present?

    total = scope.count
    puts "Encontrados #{total} mensajes con vcard crudo."

    fixed = 0
    scope.find_each do |message|
      contacts = Twilio::VcardContactParserService.new(text: message.content).call
      if contacts.blank?
        puts "  message=#{message.id}: no se pudo parsear, se deja como esta"
        next
      end

      contacts.each do |contact|
        phones = contact[:phones].presence || ['Phone number is not available']
        phones.each do |phone|
          message.attachments.create!(
            account_id: message.account_id,
            file_type: :contact,
            fallback_title: phone,
            meta: { firstName: contact[:name] }.compact
          )
        end
      end
      # Quita solo el bloque vcard -- si hubiera texto real antes/despues
      # (ej. una linea en blanco, o un mensaje real mezclado), se conserva
      # en vez de borrar todo el mensaje.
      message.update!(content: Twilio::VcardContactParserService.strip_vcard_blocks(message.content).presence)
      fixed += 1
    end

    puts "Listo: #{fixed}/#{total} mensajes corregidos."
  end
end

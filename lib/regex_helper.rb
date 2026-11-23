module RegexHelper
  # user https://rubular.com/ to quickly validate your regex

  # the following regext needs atleast one character which should be
  # valid unicode letter, unicode number, underscore, hyphen
  # shouldn't start with a underscore or hyphen
  UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE = Regexp.new('\A[\p{L}\p{N}]+[\p{L}\p{N}_-]+\Z')
  # Regex to match mention markdown links and extract display names
  # Matches: [@display name](mention://user|team/id/url_encoded_name)
  # Captures: 1) @display name (including emojis), 2) url_encoded_name
  # Uses [^]]+ to match any characters except ] in display name to support emojis
  # NOTE: Still used by Slack integration (lib/integrations/slack/send_on_slack_service.rb)
  # while notifications use CommonMarker for better markdown processing
  MENTION_REGEX = Regexp.new('\[(@[^\\]]+)\]\(mention://(?:user|team)/\d+/([^)]+)\)')

  TWILIO_CHANNEL_SMS_REGEX = Regexp.new('\A\+\d{1,15}\z')
  WHATSAPP_BSUID_PATTERN = '[A-Z]{2}\.(?:ENT\.)?[A-Za-z0-9]{1,128}'.freeze
  WHATSAPP_BSUID_REGEX = Regexp.new("\\A#{WHATSAPP_BSUID_PATTERN}\\z")
  # Identificador sintetico SOLO para Import::WhatsappChatImportService --
  # un export de WhatsApp de un contacto que usa el "nombre de usuario"
  # nuevo de WhatsApp (sin numero visible) no trae ningun identificador real
  # de Meta/Twilio (ni telefono ni BSUID), asi que no hay forma de construir
  # un source_id que coincida con un webhook real. Nunca lo generara un
  # webhook de Twilio/Meta, asi que no puede chocar con un identificador
  # real -- estas conversaciones quedan como historial de solo lectura hasta
  # que se conozca el telefono real del contacto.
  WHATSAPP_IMPORT_USERNAME_PATTERN = '@[A-Za-z0-9_.]{1,128}'.freeze
  TWILIO_CHANNEL_WHATSAPP_REGEX = Regexp.new(
    "\\A(?:whatsapp:\\+\\d{1,15}|whatsapp:#{WHATSAPP_BSUID_PATTERN}|whatsapp:#{WHATSAPP_IMPORT_USERNAME_PATTERN})\\z"
  )
  WHATSAPP_CHANNEL_REGEX = Regexp.new("\\A(?:\\d{1,15}|#{WHATSAPP_BSUID_PATTERN}|#{WHATSAPP_IMPORT_USERNAME_PATTERN})\\z")
end

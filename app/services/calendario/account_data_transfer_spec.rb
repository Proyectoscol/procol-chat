# Fuente única de verdad del "qué se exporta/importa y en qué orden" -- usado
# por Calendario::AccountDataExportService y Calendario::AccountDataImportService
# para que los dos lados coincidan siempre. Ver plan de migración a producción
# (docs: data_imports/calendario_agendas_dr_corrales_2026/README.md).
#
# Deliberadamente NO incluye automatizaciones (Calendario::AppointmentEventTrigger,
# WelcomeBotFlow, MessageTemplate, ReturningAppointmentPromptConfig, BotSession)
# -- decisión explícita del usuario: esas se configuran de nuevo en cada
# instancia, revisadas con calma antes de activarlas con pacientes reales.
#
# `fk_remaps`: columnas que son FK a OTRO modelo de esta misma lista -- al
# importar, el id viejo se traduce al nuevo usando el mapa de esa clave ya
# construido (los modelos se procesan en orden, así que su mapa ya existe).
# Las columnas que NO aparecen aquí ni en `exclude` se copian tal cual
# (timestamps, campos de texto, booleanos, etc.)
module Calendario::AccountDataTransferSpec
  FORMAT_VERSION = 1

  MODELS = [
    {
      key: 'specialties',
      scope: ->(account) { account.calendario_specialties },
      exclude: [],
      fk_remaps: {}
    },
    {
      key: 'payers',
      scope: ->(account) { account.calendario_payers },
      exclude: [],
      fk_remaps: {}
    },
    {
      key: 'professionals',
      scope: ->(account) { account.calendario_professionals },
      # user_id es el usuario/agente de Chatwoot que atiende ese profesional --
      # no existe el mismo id en la cuenta destino, se vincula a mano despues.
      exclude: %w[user_id],
      fk_remaps: { 'specialty_id' => 'specialties' }
    },
    {
      key: 'services',
      scope: ->(account) { account.calendario_services },
      exclude: [],
      fk_remaps: {}
    },
    {
      key: 'service_professionals',
      scope: ->(account) { Calendario::ServiceProfessional.joins(:service).where(calendario_services: { account_id: account.id }) },
      exclude: [],
      fk_remaps: { 'service_id' => 'services', 'professional_id' => 'professionals' }
    },
    {
      key: 'service_prices',
      scope: ->(account) { Calendario::ServicePrice.joins(:service).where(calendario_services: { account_id: account.id }) },
      exclude: [],
      fk_remaps: { 'service_id' => 'services', 'payer_id' => 'payers' }
    },
    {
      key: 'professional_availabilities',
      scope: ->(account) { Calendario::ProfessionalAvailability.joins(:professional).where(calendario_professionals: { account_id: account.id }) },
      exclude: [],
      fk_remaps: { 'professional_id' => 'professionals' }
    },
    {
      key: 'contacts',
      scope: ->(account) { account.contacts },
      exclude: [],
      fk_remaps: { 'payer_id' => 'payers' }
    },
    {
      key: 'contact_inboxes',
      scope: ->(account) { ContactInbox.joins(:contact).where(contacts: { account_id: account.id }) },
      # inbox_id/source_id/hmac_verified/pubsub_token son especificos de la
      # bandeja de origen -- el import genera un source_id fresco para la
      # bandeja de DESTINO que el usuario elija (ver import service).
      exclude: %w[inbox_id source_id hmac_verified pubsub_token],
      fk_remaps: { 'contact_id' => 'contacts' }
    },
    {
      key: 'conversations',
      scope: ->(account) { account.conversations },
      # inbox_id lo decide el import (una sola bandeja destino para todo el
      # lote); assignee/team/campaign son conceptos de la cuenta de origen.
      exclude: %w[inbox_id assignee_id team_id campaign_id uuid display_id],
      fk_remaps: { 'contact_id' => 'contacts', 'contact_inbox_id' => 'contact_inboxes' }
    },
    {
      key: 'messages',
      scope: ->(account) { account.messages },
      # inbox_id igual que conversations; sender_id se maneja aparte (puede
      # ser un Contact, que si se remapea, o un User, que no existe en destino).
      exclude: %w[inbox_id sender_id],
      fk_remaps: { 'conversation_id' => 'conversations' }
    },
    {
      key: 'attachments',
      scope: ->(account) { Attachment.joins(:message).where(messages: { account_id: account.id }) },
      exclude: [],
      fk_remaps: { 'message_id' => 'messages' }
    },
    {
      key: 'open_days',
      scope: ->(account) { account.calendario_open_days },
      exclude: %w[opened_by_id],
      fk_remaps: { 'professional_id' => 'professionals' }
    },
    {
      key: 'appointments',
      scope: ->(account) { account.calendario_appointments },
      exclude: %w[created_by_id],
      fk_remaps: { 'professional_id' => 'professionals', 'service_id' => 'services', 'contact_id' => 'contacts',
                   'conversation_id' => 'conversations' }
    },
    {
      key: 'appointment_audit_logs',
      scope: ->(account) { Calendario::AppointmentAuditLog.joins(:appointment).where(calendario_appointments: { account_id: account.id }) },
      exclude: %w[user_id],
      fk_remaps: { 'appointment_id' => 'appointments' }
    },
    {
      key: 'waitlist_entries',
      scope: ->(account) { account.calendario_waitlist_entries },
      exclude: [],
      fk_remaps: { 'contact_id' => 'contacts', 'professional_id' => 'professionals', 'service_id' => 'services',
                   'fulfilled_by_appointment_id' => 'appointments' }
    },
    {
      key: 'contact_session_credits',
      scope: ->(account) { account.calendario_contact_session_credits },
      exclude: [],
      fk_remaps: { 'contact_id' => 'contacts', 'granted_by_appointment_id' => 'appointments', 'consumed_by_appointment_id' => 'appointments' }
    }
  ].freeze

  def self.model_class_for(key)
    {
      'specialties' => Calendario::Specialty,
      'payers' => Calendario::Payer,
      'professionals' => Calendario::Professional,
      'services' => Calendario::Service,
      'service_professionals' => Calendario::ServiceProfessional,
      'service_prices' => Calendario::ServicePrice,
      'professional_availabilities' => Calendario::ProfessionalAvailability,
      'contacts' => Contact,
      'contact_inboxes' => ContactInbox,
      'conversations' => Conversation,
      'messages' => Message,
      'attachments' => Attachment,
      'open_days' => Calendario::OpenDay,
      'appointments' => Calendario::Appointment,
      'appointment_audit_logs' => Calendario::AppointmentAuditLog,
      'waitlist_entries' => Calendario::WaitlistEntry,
      'contact_session_credits' => Calendario::ContactSessionCredit
    }.fetch(key)
  end
end

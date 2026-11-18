# Fase 0 del plan de Notificaciones (ver docs/designs/
# calendario-bienvenida-bot-notificaciones.md) -- crea los
# Calendario::AppointmentEventTrigger de "Confirmacion de cita por servicio" +
# "Recordatorio 24h/1h" directamente en la base de datos, en vez de que el
# usuario los teclee uno por uno en la UI.
#
# Idempotente: cada trigger se busca por (trigger_kind, service_ids, payer_kinds,
# target_status, inbox_id) antes de crear, asi que correrlo de nuevo no duplica.
#
# El texto es deliberadamente generico -- pedido explicito del usuario: en
# produccion esto se reemplaza por una plantilla real de WhatsApp (con imagen/
# carrusel de preparacion aprobada en Twilio/Meta), asi que el texto de aqui
# nunca es lo que el paciente ve al final, solo sirve para probar que las
# variables y el enrutamiento por servicio/pagador quedan bien armados.
#
# test_mode: true a proposito -- la bandeja de esta cuenta es Channel::TwilioSms
# (no Channel::Whatsapp), que no tiene catalogo de plantillas aprobadas (ver
# AppointmentEventTriggerFormModal.vue#selectedInboxIsMetaWhatsapp); sin
# test_mode, send_template_message buscaria una plantilla inexistente llamada
# "custom_test" y no haria nada. test_mode crea una nota privada visible,
# util para verificar el texto antes de pasar a produccion.
#
# Uso:
#   bundle exec rails runner script/seed_calendario_notification_triggers.rb
#   ACCOUNT_ID=2 bundle exec rails runner script/seed_calendario_notification_triggers.rb

account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
inbox = account.inboxes.find_by(channel_type: 'Channel::TwilioSms') ||
        account.inboxes.find_by(channel_type: 'Channel::Whatsapp')
raise "No hay ninguna bandeja de WhatsApp en la cuenta #{account.id}" unless inbox

services = account.calendario_services.index_by(&:name)

EPS_LIKE_PAYER_KINDS = %w[eps plan_complementario prepagada poliza].freeze

BASE_DEBE_TRAER = <<~TEXT.strip
  Debe traer:
  Historia clínica
  Orden médica
  Copia de cédula
TEXT

def find_or_create_trigger!(account:, inbox:, trigger_kind:, body:, service_ids: [], payer_kinds: [], target_status: nil,
                            offset_minutes: nil)
  existing = account.calendario_appointment_event_triggers.find do |t|
    t.trigger_kind == trigger_kind &&
      t.inbox_id == inbox.id &&
      t.service_ids.sort == service_ids.sort &&
      t.payer_kinds.sort == payer_kinds.sort &&
      t.target_status == target_status &&
      t.offset_minutes == offset_minutes
  end
  if existing
    puts "YA EXISTE (id=#{existing.id}): #{trigger_kind} service_ids=#{service_ids} payer_kinds=#{payer_kinds}"
    return existing
  end

  trigger = account.calendario_appointment_event_triggers.create!(
    trigger_kind: trigger_kind, inbox: inbox, active: true, test_mode: true,
    service_ids: service_ids, payer_kinds: payer_kinds, target_status: target_status, offset_minutes: offset_minutes,
    template_params: { name: 'custom_test', category: 'custom', language: nil, namespace: nil, processed_params: { body: body } }
  )
  puts "CREADO (id=#{trigger.id}): #{trigger_kind} service_ids=#{service_ids} payer_kinds=#{payer_kinds}"
  trigger
end

# --- Confirmacion por servicio (on_create) -------------------------------

# Consulta: el precio/forma de pago cambia entre particular y EPS -- texto
# distinto a proposito, nunca los dos triggers aplican a la vez (payer_kinds
# no se superponen, ver Calendario::AppointmentEventTrigger#applies_to?).
if (consulta = services['Consulta'])
  find_or_create_trigger!(
    account: account, inbox: inbox, trigger_kind: 'on_create',
    service_ids: [consulta.id], payer_kinds: ['particular'],
    body: <<~TEXT.strip
      Cita {{ appointment.service_name }}
      {{ contact.name }}
      {{ appointment.date }}
      Hora {{ appointment.time }}

      Valor: $280.000
      Por favor en efectivo, no contamos con datáfono.

      #{BASE_DEBE_TRAER}

      Por favor confirmar
    TEXT
  )
  find_or_create_trigger!(
    account: account, inbox: inbox, trigger_kind: 'on_create',
    service_ids: [consulta.id], payer_kinds: EPS_LIKE_PAYER_KINDS,
    body: <<~TEXT.strip
      Cita {{ appointment.service_name }}
      {{ contact.name }}
      {{ appointment.date }}
      Hora {{ appointment.time }}

      #{BASE_DEBE_TRAER}
      Número de vale/autorización de su EPS

      Por favor confirmar
    TEXT
  )
end

# Urodinamia / Uroflujometria: evidencia real de los chats -- pacientes
# remitidos (ej. San Jorge) traen su propio paquete de documentos.
if (urodinamia = services['Urodinamia'])
  find_or_create_trigger!(
    account: account, inbox: inbox, trigger_kind: 'on_create',
    service_ids: [urodinamia.id],
    body: <<~TEXT.strip
      Cita {{ appointment.service_name }}
      {{ contact.name }}
      {{ appointment.date }}
      Hora {{ appointment.time }}

      Debe traer:
      El paquete de documentos de su remisión (o historia clínica + orden médica)
      Copia de cédula

      Por favor confirmar
      Leer la preparación
    TEXT
  )
end

if (uroflujometria = services['Uroflujometria'])
  find_or_create_trigger!(
    account: account, inbox: inbox, trigger_kind: 'on_create',
    service_ids: [uroflujometria.id],
    body: <<~TEXT.strip
      Cita {{ appointment.service_name }}
      {{ contact.name }}
      {{ appointment.date }}
      Hora {{ appointment.time }}

      #{BASE_DEBE_TRAER}

      Por favor confirmar
      Leer la preparación
    TEXT
  )
end

# Cistoscopia: ropa comoda, mencionado explicitamente por el usuario.
if (cistoscopia = services['Cistoscopia'])
  find_or_create_trigger!(
    account: account, inbox: inbox, trigger_kind: 'on_create',
    service_ids: [cistoscopia.id],
    body: <<~TEXT.strip
      Cita {{ appointment.service_name }}
      {{ contact.name }}
      {{ appointment.date }}
      Hora {{ appointment.time }}

      #{BASE_DEBE_TRAER}
      Venir con ropa cómoda

      Por favor confirmar
    TEXT
  )
end

# El resto de servicios (procedimientos/controles) -- texto generico por
# ahora, sin service_ids especifico para no repetir el mismo trigger 10
# veces: uno solo que aplica a "todos los servicios restantes" se logra
# dejando service_ids vacio, pero eso chocaria con los triggers especificos
# de arriba (un servicio cubierto por dos triggers on_create mandaria dos
# mensajes). Se listan explicitamente los servicios sin cobertura especifica.
GENERIC_SERVICE_NAMES = [
  'Control', 'Biopsia de prostata', 'Cauterizacion', 'Conizacion', 'Litotricia', 'Pesario',
  'Post quirurgico', 'Retiro de cateter', 'Sexologia', 'Vasectomia'
].freeze
generic_service_ids = GENERIC_SERVICE_NAMES.filter_map { |name| services[name]&.id }
if generic_service_ids.any?
  find_or_create_trigger!(
    account: account, inbox: inbox, trigger_kind: 'on_create',
    service_ids: generic_service_ids,
    body: <<~TEXT.strip
      Cita {{ appointment.service_name }}
      {{ contact.name }}
      {{ appointment.date }}
      Hora {{ appointment.time }}

      #{BASE_DEBE_TRAER}

      Por favor confirmar
    TEXT
  )
end
missing = GENERIC_SERVICE_NAMES - services.keys
puts "AVISO: servicios no encontrados en esta cuenta (se omiten): #{missing.join(', ')}" if missing.any?

# --- Recordatorios (before_start) -----------------------------------------

find_or_create_trigger!(
  account: account, inbox: inbox, trigger_kind: 'before_start', offset_minutes: 1440,
  body: <<~TEXT.strip
    Hola {{ contact.name }}, le recordamos su cita de {{ appointment.service_name }} mañana {{ appointment.date }} a las {{ appointment.time }}.
  TEXT
)

# --- No asistio (Fase 1) ---------------------------------------------------
# El texto literal "Reprogramar"/"Cancelar" es a proposito -- es lo que
# Calendario::NoShowReplyListener reconoce cuando el paciente responde (ver
# app/listeners/calendario/no_show_reply_listener.rb). offset_minutes vacio =
# instantaneo (ver Calendario::AppointmentEventTrigger#delay_minutes).
find_or_create_trigger!(
  account: account, inbox: inbox, trigger_kind: 'on_status_change', target_status: 'no_show',
  body: <<~TEXT.strip
    Hola {{ contact.name }}, notamos que no pudo asistir a su cita de {{ appointment.service_name }} de hoy.

    Responda:
    Reprogramar
    Cancelar
  TEXT
)

find_or_create_trigger!(
  account: account, inbox: inbox, trigger_kind: 'before_start', offset_minutes: 60,
  body: <<~TEXT.strip
    Hola {{ contact.name }}, le recordamos que su cita de {{ appointment.service_name }} es hoy a las {{ appointment.time }}.
  TEXT
)

puts "\nTotal triggers en la cuenta #{account.id}: #{account.calendario_appointment_event_triggers.count}"

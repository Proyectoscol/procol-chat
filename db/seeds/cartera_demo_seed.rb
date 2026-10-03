# Datos ficticios de Cartera para tomar screenshots: clientes, facturas,
# pagos, inboxes/conversaciones/mensajes y notas - comercialmente
# coherentes (varios perfiles de pago, varios volúmenes de facturación,
# mezcla de cartera vigente/vencida/por vencer). NINGÚN puntaje de riesgo,
# tramo o nivel de escalamiento se hardcodea: todo lo calcula el motor real
# (Cartera::PriorizacionService / PrescripcionService) al final del script,
# igual que lo haría un sync real contra Alegra.
#
# Uso:
#   CARTERA_DEMO_ACCOUNT_ID=3 bundle exec rails runner db/seeds/cartera_demo_seed.rb
#
# Es re-corrible: borra primero cualquier corrida anterior de esta semilla
# (identificada por el prefijo DEMO- en external_id) antes de crear de nuevo,
# así que se puede ajustar y re-ejecutar sin acumular duplicados. Para
# empezar desde cero total (incluyendo datos reales de un sync), correr antes
# db/seeds/cartera_demo_wipe.rb.
#
# rubocop:disable Rails/Output -- script de consola, el puts es la salida que se necesita ver en vivo

account = if ENV['CARTERA_DEMO_ACCOUNT_ID'].present?
            Account.find(ENV['CARTERA_DEMO_ACCOUNT_ID'])
          else
            candidatas = Account.all.select { |a| a.feature_enabled?('cartera') }
            unless candidatas.size == 1
              raise "Hay #{candidatas.size} cuentas con cartera activo (#{candidatas.map(&:id)}). " \
                    'Define CARTERA_DEMO_ACCOUNT_ID=<id> y corre de nuevo.'
            end

            candidatas.first
          end

puts "== Sembrando datos demo en cuenta #{account.id} (#{account.name}) =="

DEMO_PREFIX = 'DEMO-'.freeze
DEMO_EMAIL_DOMAIN = 'cartera-demo.local'.freeze
HOY = Time.zone.now
RNG = Random.new(20_261_003)
AUTOR = account.administrators.first || account.users.first
SUCURSALES = %w[Bogotá Medellín Cali Barranquilla].freeze

# ----------------------------------------------------------------------------
# Limpieza de una corrida anterior de esta misma semilla (idempotente).
# ----------------------------------------------------------------------------
previos = account.cartera_clientes.where('external_id LIKE ?', "#{DEMO_PREFIX}%")
puts "Borrando #{previos.count} clientes demo de una corrida anterior..." if previos.any?
previos.find_each(&:destroy!)

# Los contactos demo se identifican por dominio de correo, no por el link a
# Cliente - así una corrida anterior de cartera_demo_wipe.rb (que borra
# clientes pero nunca Contacts) no deja huérfanos que choquen con los
# nuevos por email/teléfono duplicado.
contactos_demo = account.contacts.where('email LIKE ?', "%@#{DEMO_EMAIL_DOMAIN}")
puts "Borrando #{contactos_demo.count} contactos demo de una corrida anterior..." if contactos_demo.any?
contactos_demo.find_each do |contact|
  contact.conversations.destroy_all
  contact.notes.destroy_all
  contact.destroy!
end
account.inboxes.where('name LIKE ?', 'Demo –%').destroy_all

# ----------------------------------------------------------------------------
# Inboxes ficticios (Channel::Api: no requiere credenciales reales).
# ----------------------------------------------------------------------------
whatsapp_inbox = Inbox.create!(account: account, channel: Channel::Api.create!(account: account), name: 'Demo – WhatsApp Cobranza')
email_inbox = Inbox.create!(account: account, channel: Channel::Api.create!(account: account), name: 'Demo – Correo Cobranza')
puts "Inboxes creados: #{whatsapp_inbox.name} (##{whatsapp_inbox.id}), #{email_inbox.name} (##{email_inbox.id})"

# ----------------------------------------------------------------------------
# Helpers de generación
# ----------------------------------------------------------------------------
NOMBRES_EMPRESA = %w[
  Distribuciones Comercializadora Industrias Soluciones Grupo Suministros
  Ferretería Textiles Alimentos Logística Repuestos Construcciones
].freeze
SUFIJOS_EMPRESA = [
  'del Norte', 'Andina', 'La Esperanza', 'El Progreso', 'Continental', 'Nacional',
  'San Jorge', 'La Castellana', 'Los Andes', 'del Valle', 'Metropolitana', 'Central'
].freeze
NOMBRES_PERSONA = %w[Carlos Maria Jorge Luisa Andres Patricia Felipe Daniela Ricardo Sandra Mauricio Claudia].freeze
APELLIDOS_PERSONA = %w[Gómez Rodríguez Martínez López Pérez Hernández García Díaz Torres Ramírez].freeze

contador_nombre = 0

generar_nombre = lambda do |tipo_deudor|
  contador_nombre += 1
  if tipo_deudor == :persona_natural
    "#{NOMBRES_PERSONA.sample(random: RNG)} #{APELLIDOS_PERSONA.sample(random: RNG)}"
  else
    "#{NOMBRES_EMPRESA.sample(random: RNG)} #{SUFIJOS_EMPRESA.sample(random: RNG)} #{contador_nombre}"
  end
end

generar_identificacion = lambda do |tipo_deudor|
  tipo_deudor == :persona_natural ? RNG.rand(10_000_000..1_200_000_000).to_s : "9#{RNG.rand(10_000_000..99_999_999)}"
end

# Formato local (como llega de Alegra), sin +57 - el +57 lo agrega
# Cartera::IndicativoTelefonico.formatear_e164 al crear el Contact, igual
# que hace SyncService#vincular_contacto con datos reales.
generar_telefono = -> { "3#{RNG.rand(0..2)}#{RNG.rand(1_000_000..9_999_999)}" }

# Plantillas de mensajes de cobro / respuestas de cliente, usadas solo como
# contenido de demo para las conversaciones - no se envían de verdad.
PLANTILLAS_SALIENTES = [
  'Hola %<nombre>s, te recordamos que la factura %<numero>s por %<valor>s vence el %<fecha>s. ' \
  '¿Podrías confirmarnos la fecha de pago?',
  'Hola %<nombre>s, tu factura %<numero>s por %<valor>s está vencida. Quedamos atentos a tu confirmación de pago.',
  'Buen día %<nombre>s, para tu tranquilidad adjuntamos el estado de cuenta con la factura %<numero>s pendiente por %<valor>s.'
].freeze
RESPUESTAS_ENTRANTES = [
  'Claro, quedo pendiente de hacer el pago esta semana.',
  'Ya realicé la transferencia, en un momento les comparto el comprobante.',
  '¿Me pueden confirmar el número de cuenta para el pago?',
  'Tuvimos un inconveniente de flujo de caja, ¿podemos acordar una fecha nueva?',
  'Gracias por el recordatorio, quedamos atentos.'
].freeze
NOTAS_INTERACCION = [
  'Se llamó al cliente, promete pago antes de fin de mes.',
  'Cliente indica que el área de tesorería procesa pagos los viernes.',
  'Se envió estado de cuenta actualizado por correo.',
  'Cliente en mora reiterada, escalar a prejurídico si no hay respuesta.',
  'Se acordó plan de pago en dos cuotas, primera cuota pendiente.',
  'No contesta llamadas, se deja mensaje de voz.'
].freeze

# rubocop:disable Metrics/BlockLength, Rails/SkipsModelValidations -- generador cohesivo
# de demo; update_columns es deliberado para fijar fechas pasadas de mensajes/notas.
crear_contacto_y_canales = lambda do |nombre, telefono, email, sucursal, con_conversacion|
  telefono_e164 = Cartera::IndicativoTelefonico.formatear_e164(telefono, sucursal)
  contact = account.contacts.create!(name: nombre, phone_number: telefono_e164, email: email)

  wa_contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: whatsapp_inbox, source_id: SecureRandom.uuid, hmac_verified: true).perform

  return contact unless con_conversacion

  estado_conversacion = [:open, :pending, :resolved].sample(random: RNG)
  conversation = Conversation.create!(
    account: account, inbox: whatsapp_inbox, contact: contact, contact_inbox: wa_contact_inbox,
    status: estado_conversacion, assignee: AUTOR, additional_attributes: {}
  )

  num_mensajes_salientes = RNG.rand(1..3)
  responde = RNG.rand < 0.6

  num_mensajes_salientes.times do |i|
    dias_atras = RNG.rand(2..40)
    plantilla = format(
      PLANTILLAS_SALIENTES.sample(random: RNG),
      nombre: nombre.split.first, numero: "F-DEMO-#{RNG.rand(1000..9999)}",
      valor: ActiveSupport::NumberHelper.number_to_currency(RNG.rand(200_000..3_000_000), unit: '$', precision: 0, delimiter: '.'),
      fecha: (HOY - dias_atras.days).to_date.iso8601
    )
    msg = Message.create!(
      account: account, inbox: whatsapp_inbox, conversation: conversation, sender: AUTOR,
      message_type: :outgoing, content: plantilla
    )
    msg.update_columns(created_at: HOY - dias_atras.days, updated_at: HOY - dias_atras.days)

    next unless responde && i == num_mensajes_salientes - 1

    reply = Message.create!(
      account: account, inbox: whatsapp_inbox, conversation: conversation, sender: contact,
      message_type: :incoming, content: RESPUESTAS_ENTRANTES.sample(random: RNG)
    )
    reply.update_columns(created_at: HOY - (dias_atras - 1).days, updated_at: HOY - (dias_atras - 1).days)
  end

  if RNG.rand < 0.4
    nota = account.notes.create!(contact: contact, user: ([AUTOR].compact.sample(random: RNG)), content: NOTAS_INTERACCION.sample(random: RNG))
    nota.update_columns(created_at: HOY - RNG.rand(1..30).days)
  end

  contact
end
# rubocop:enable Metrics/BlockLength, Rails/SkipsModelValidations

# valor_factura dentro de un rango creible relativo al cupo del cliente.
valor_factura = ->(cupo) { (cupo * RNG.rand(0.04..0.22)).round(-4).clamp(150_000, cupo * 0.5) }

# Crea una factura histórica. `desenlace` decide si queda paga (a tiempo o
# tarde, según `offset_dias`) o abierta y vencida (para poblar tramos de
# aging vencido).
crear_factura_historica = lambda do |cliente, cupo, dias_emision_atras, plazo_dias, desenlace, offset_pago_dias, idx|
  fecha_emision = HOY - dias_emision_atras.days
  fecha_vencimiento = fecha_emision + plazo_dias.days
  valor = valor_factura.call(cupo)

  factura = account.cartera_facturas.create!(
    cliente: cliente, external_id: "#{DEMO_PREFIX}#{cliente.external_id}-H#{idx}",
    numero: "FV-#{cliente.external_id}-#{idx}", fecha_emision: fecha_emision, fecha_vencimiento: fecha_vencimiento,
    valor_total: valor, saldo_pendiente: desenlace == :abierta ? valor : 0
  )

  return factura if desenlace == :abierta

  fecha_pago = [fecha_vencimiento + offset_pago_dias.days, HOY].min
  pago = cliente.pagos.create!(
    account: account, external_id: "#{DEMO_PREFIX}#{cliente.external_id}-P#{idx}",
    fecha: fecha_pago, valor: valor, medio_pago: %w[transferencia efectivo cheque].sample(random: RNG)
  )
  pago.aplicaciones_pago.create!(account: account, factura: factura, valor_aplicado: valor)
  factura
end

crear_factura_futura = lambda do |cliente, cupo, dias_hasta_vencer, idx|
  fecha_emision = HOY - RNG.rand(1..10).days
  fecha_vencimiento = HOY + dias_hasta_vencer.days
  valor = valor_factura.call(cupo)

  account.cartera_facturas.create!(
    cliente: cliente, external_id: "#{DEMO_PREFIX}#{cliente.external_id}-F#{idx}",
    numero: "FV-#{cliente.external_id}-F#{idx}", fecha_emision: fecha_emision, fecha_vencimiento: fecha_vencimiento,
    valor_total: valor, saldo_pendiente: valor
  )
end

# ----------------------------------------------------------------------------
# Arquetipos de cliente: cada uno exagera un comportamiento de pago real
# (buen pagador, pagador ocasionalmente tarde, mal pagador crónico, mora de
# muy larga data, cerca del límite de prescripción, estratégico/no-cobrar,
# cliente nuevo) para que el motor de riesgo calcule puntajes repartidos en
# todo el rango 0-100 en vez de agrupados en un solo punto.
# ----------------------------------------------------------------------------
ARQUETIPOS = [
  { nombre: 'excelente_bajo_volumen', n: 4, tipo_deudor: :empresa, n_hist: 3, n_fut: 1, pct_tarde: 0.0, offset_tarde: 0, cupo: 8_000_000..20_000_000,
    abiertas_vencidas: 0 },
  { nombre: 'excelente_alto_volumen', n: 3, tipo_deudor: :empresa, n_hist: 16, n_fut: 3, pct_tarde: 0.1, offset_tarde: 10,
    cupo: 40_000_000..90_000_000, abiertas_vencidas: 0 },
  { nombre: 'promedio', n: 5, tipo_deudor: :empresa, n_hist: 8, n_fut: 2, pct_tarde: 0.35, offset_tarde: 25, cupo: 15_000_000..35_000_000,
    abiertas_vencidas: 1 },
  { nombre: 'mal_pagador_cronico', n: 4, tipo_deudor: :empresa, n_hist: 10, n_fut: 1, pct_tarde: 0.75, offset_tarde: 70,
    cupo: 10_000_000..20_000_000, abiertas_vencidas: 4 },
  { nombre: 'pesimo_pagador', n: 2, tipo_deudor: :empresa, n_hist: 12, n_fut: 0, pct_tarde: 0.97, offset_tarde: 150, emision_min: 220,
    cupo: 3_000_000..6_000_000, abiertas_vencidas: 7 },
  { nombre: 'mora_larga', n: 2, tipo_deudor: :empresa, n_hist: 9, n_fut: 1, pct_tarde: 0.5, offset_tarde: 40, cupo: 12_000_000..20_000_000,
    abiertas_vencidas: 2, forzar_mas_360: true },
  { nombre: 'cerca_prescripcion', n: 2, tipo_deudor: :persona_natural, n_hist: 6, n_fut: 0, pct_tarde: 0.4, offset_tarde: 35,
    cupo: 5_000_000..10_000_000, abiertas_vencidas: 1, forzar_prescripcion: true },
  { nombre: 'estrategico', n: 2, tipo_deudor: :empresa, n_hist: 7, n_fut: 2, pct_tarde: 0.3, offset_tarde: 20, cupo: 20_000_000..50_000_000,
    abiertas_vencidas: 1, estrategico: true },
  { nombre: 'cliente_nuevo', n: 2, tipo_deudor: :persona_natural, n_hist: 1, n_fut: 1, pct_tarde: 0.0, offset_tarde: 0, cupo: 3_000_000..8_000_000,
    abiertas_vencidas: 0 }
].freeze

TRAMOS_VENCIDO_OBJETIVO = [15, 45, 75, 150, 300, 500].freeze # dias atras aprox para pisar cada tramo de aging
DIAS_FUTUROS_OBJETIVO = [10, 45, 75, 150, 300, 500].freeze # dias adelante aprox para pisar cada tramo de por_vencer
PLAZOS_CREDITO = [15, 30, 45, 60].freeze

clientes_creados = []

# rubocop:disable Metrics/BlockLength -- generador cohesivo de clientes+facturas demo
ARQUETIPOS.each do |arq|
  arq[:n].times do |i|
    nombre = generar_nombre.call(arq[:tipo_deudor])
    identificacion = generar_identificacion.call(arq[:tipo_deudor])
    cupo = RNG.rand(arq[:cupo])
    external_id = "#{DEMO_PREFIX}#{arq[:nombre]}-#{i}"
    telefono = generar_telefono.call
    email = "contacto#{clientes_creados.size + 1}.#{arq[:nombre].tr('_', '-')}@#{DEMO_EMAIL_DOMAIN}"

    sucursal = SUCURSALES.sample(random: RNG)
    cliente = account.cartera_clientes.create!(
      external_id: external_id, identificacion: identificacion, nombre: nombre, tipo_deudor: arq[:tipo_deudor],
      telefono: telefono, email: email, sucursal: sucursal,
      cupo_asignado: cupo, es_estrategico: arq.fetch(:estrategico, false)
    )

    # Facturas históricas: una fracción queda ABIERTA Y VENCIDA (para poblar
    # tramos de aging), el resto se paga a tiempo o tarde según el arquetipo.
    abiertas_pendientes = arq[:abiertas_vencidas]
    emision_min = arq.fetch(:emision_min, 45)
    arq[:n_hist].times do |h|
      dias_emision_atras = RNG.rand(emision_min..420)
      plazo = PLAZOS_CREDITO.sample(random: RNG)

      if abiertas_pendientes.positive? && dias_emision_atras > plazo
        dias_vencido_objetivo = if arq[:forzar_mas_360] && abiertas_pendientes == arq[:abiertas_vencidas]
                                  RNG.rand(380..650)
                                elsif arq[:forzar_prescripcion] && abiertas_pendientes == arq[:abiertas_vencidas]
                                  RNG.rand(1000..1050)
                                else
                                  TRAMOS_VENCIDO_OBJETIVO.sample(random: RNG)
                                end
        dias_emision_atras = dias_vencido_objetivo + plazo
        crear_factura_historica.call(cliente, cupo, dias_emision_atras, plazo, :abierta, 0, h)
        abiertas_pendientes -= 1
        next
      end

      tarde = RNG.rand < arq[:pct_tarde]
      offset = tarde ? RNG.rand((arq[:offset_tarde] * 0.6).round..(arq[:offset_tarde] * 1.4).round) : RNG.rand(-5..3)
      crear_factura_historica.call(cliente, cupo, dias_emision_atras, plazo, :pagada, offset, h)
    end

    # Facturas futuras (abiertas, aún no vencen): reparten la cartera "por
    # vencer" entre varios tramos en vez de amontonarlas todas en uno.
    arq[:n_fut].times do |f|
      dias_adelante = DIAS_FUTUROS_OBJETIVO.sample(random: RNG) + RNG.rand(-5..5)
      crear_factura_futura.call(cliente, cupo, dias_adelante.clamp(3, 600), f)
    end

    con_conversacion = RNG.rand < 0.75
    contact = crear_contacto_y_canales.call(nombre, telefono, email, sucursal, con_conversacion)
    cliente.update!(contact_id: contact.id)

    clientes_creados << cliente
  end
end
# rubocop:enable Metrics/BlockLength

puts "Clientes creados: #{clientes_creados.size}"
puts "Facturas creadas: #{account.cartera_facturas.where('external_id LIKE ?', "#{DEMO_PREFIX}%").count}"
puts "Pagos creados:    #{Cartera::Pago.where('external_id LIKE ?', "#{DEMO_PREFIX}%").count}"

# ----------------------------------------------------------------------------
# Recalcular con el motor real - nada de lo anterior fija puntaje de riesgo,
# tramo de aging ni nivel de escalamiento directamente.
# ----------------------------------------------------------------------------
puts
puts '-- Recalculando priorización y prescripción con el motor real --'
resultado_priorizacion = Cartera::PriorizacionService.new(account).recalcular
resultado_prescripcion = Cartera::PrescripcionService.new(account).recalcular
puts "Priorización: #{resultado_priorizacion.inspect}"
puts "Prescripción: #{resultado_prescripcion.inspect}"

resumen = Cartera::AgingService.new(account).calcular_resumen
puts
puts '-- Resumen resultante --'
puts "Saldo vigente:    #{resumen[:valor_vigente]}"
puts "Saldo vencido:    #{resumen[:valor_vencido]}"
puts "Cupo total:       #{resumen[:cupo_total]}"
puts "Cupo disponible:  #{resumen[:cupo_disponible]}"
puts "Tramos aging:     #{resumen[:tramos].map { |t| "#{t[:tramo]}=#{t[:cantidad_facturas]}" }.join(', ')}"
puts "Tramos por vencer: #{resumen[:por_vencer].map { |t| "#{t[:tramo]}=#{t[:cantidad_facturas]}" }.join(', ')}"

puntajes = account.cartera_casos.where.not(puntaje_riesgo: nil).pluck(:puntaje_riesgo)
puts "Puntajes de riesgo: min=#{puntajes.min} max=#{puntajes.max} promedio=#{(puntajes.sum.to_f / puntajes.size).round(1)}"
puts
puts '== Listo. Refresca /cartera/resumen, /cartera/clientes y /cartera/facturas. =='
# rubocop:enable Rails/Output

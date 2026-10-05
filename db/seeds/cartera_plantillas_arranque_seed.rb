# Tres borradores de plantilla de WhatsApp listos para enviar a aprobacion -
# mora corta, mora media y prejuridico -, cada uno con sus variables {{n}}
# ya mapeadas a un campo real (Cartera::Campanas::VariableResolver). Para
# entregar la plataforma a un cliente nuevo: correr esto una vez, conectar
# su inbox de WhatsApp, y desde Campañas > Plantillas solo falta pedir la
# aprobacion de cada una.
#
# Uso:
#   CARTERA_PLANTILLAS_ACCOUNT_ID=3 bundle exec rails runner db/seeds/cartera_plantillas_arranque_seed.rb
#
# Es re-corrible: borra primero cualquier borrador propio (nombre con el
# prefijo ARRANQUE_PREFIX) que aun no se haya enviado a Twilio, y los vuelve
# a crear - nunca toca una plantilla que ya tenga content_sid.
#
# rubocop:disable Rails/Output -- script de consola, el puts es la salida que se necesita ver en vivo

account = if ENV['CARTERA_PLANTILLAS_ACCOUNT_ID'].present?
            Account.find(ENV['CARTERA_PLANTILLAS_ACCOUNT_ID'])
          else
            candidatas = Account.all.select { |a| a.feature_enabled?('cartera') }
            unless candidatas.size == 1
              raise "Hay #{candidatas.size} cuentas con cartera activo (#{candidatas.map(&:id)}). " \
                    'Define CARTERA_PLANTILLAS_ACCOUNT_ID=<id> y corre de nuevo.'
            end

            candidatas.first
          end

puts "== Sembrando plantillas de arranque en cuenta #{account.id} (#{account.name}) =="

ARRANQUE_PREFIX = 'arranque_'.freeze

PLANTILLAS = [
  {
    nombre: "#{ARRANQUE_PREFIX}mora_corta_v1",
    categoria: 'utility',
    cuerpo: 'Hola {{1}}, te recordamos que tienes la factura {{2}} por valor de {{3}} pendiente de pago, ' \
            'vencida hace {{4}} días. Por favor realiza tu pago a la mayor brevedad. Gracias.',
    variables: {
      '1' => 'nombre_cliente',
      '2' => 'numero_factura',
      '3' => 'saldo_abierto',
      '4' => 'dias_vencido'
    }
  },
  {
    nombre: "#{ARRANQUE_PREFIX}mora_media_v1",
    categoria: 'utility',
    cuerpo: 'Hola {{1}}, tu cuenta presenta un saldo pendiente de {{2}} correspondiente a la factura {{3}}, ' \
            'con {{4}} días de mora (tramo {{5}}). Te invitamos a ponerte al día cuanto antes para evitar ' \
            'inconvenientes.',
    variables: {
      '1' => 'nombre_cliente',
      '2' => 'saldo_abierto',
      '3' => 'numero_factura',
      '4' => 'dias_vencido',
      '5' => 'tramo'
    }
  },
  {
    nombre: "#{ARRANQUE_PREFIX}prejuridico_v1",
    categoria: 'utility',
    cuerpo: 'Estimado(a) {{1}}, su obligación representada en la factura {{2}} con vencimiento {{3}} se ' \
            'encuentra en mora por {{4}} días con un saldo de {{5}}. Esta es una notificación prejurídica. ' \
            'Contáctenos para regularizar su situación y evitar acciones de cobro adicionales.',
    variables: {
      '1' => 'nombre_cliente',
      '2' => 'numero_factura',
      '3' => 'fecha_vencimiento',
      '4' => 'dias_vencido',
      '5' => 'saldo_abierto'
    }
  }
].freeze

borradas = account.cartera_plantillas_whatsapp
                  .where(content_sid: nil)
                  .where('nombre LIKE ?', "#{ARRANQUE_PREFIX}%")
                  .destroy_all
puts "Borrados #{borradas.size} borradores previos de arranque sin enviar." if borradas.any?

PLANTILLAS.each do |atributos|
  plantilla = account.cartera_plantillas_whatsapp.create!(atributos)
  puts "Creado borrador ##{plantilla.id}: #{plantilla.nombre}"
end

puts '== Listo. Desde Campañas > Plantillas: conecta el inbox de WhatsApp y pide la aprobación de cada una. =='

# rubocop:enable Rails/Output

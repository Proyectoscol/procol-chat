# Borra los datos de Cartera::* de una cuenta (clientes, facturas, pagos,
# aplicaciones de pago, notas credito, eventos radian, casos, alertas y
# corridas de sync) sin tocar los Contacts/Conversations nativos de
# Chatwoot - la asociación Cliente->Contact es `dependent: :nullify` del
# lado del Contact, así que borrar el Cliente nunca borra el Contact.
#
# Uso:
#   CARTERA_DEMO_ACCOUNT_ID=3 bundle exec rails runner db/seeds/cartera_demo_wipe.rb
#
# Si no se define CARTERA_DEMO_ACCOUNT_ID, autodetecta la única cuenta con
# el feature `cartera` activo (y falla si hay más de una o ninguna).
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

puts "== Cuenta #{account.id} (#{account.name}) =="
puts "Clientes:        #{account.cartera_clientes.count}"
puts "Facturas:        #{account.cartera_facturas.count}"
puts "Pagos:           #{Cartera::Pago.where(cliente_id: account.cartera_clientes.select(:id)).count}"
puts "Casos:           #{account.cartera_casos.count}"
puts "Alertas:         #{account.cartera_alertas.count}"
puts "Corridas sync:   #{account.cartera_corridas_sync.count}"
puts
puts '-- Borrando (no toca Contacts/Conversations) --'

ActiveRecord::Base.transaction do
  account.cartera_clientes.find_each(&:destroy!)
  account.cartera_corridas_sync.destroy_all
end

puts "Listo. Clientes restantes: #{account.cartera_clientes.count}, facturas restantes: #{account.cartera_facturas.count}"
# rubocop:enable Rails/Output

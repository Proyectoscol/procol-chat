namespace :sip do
  desc 'Escucha eventos AMI de Asterisk y envía FCM push cuando entra una llamada SIP'
  task ami_listener: :environment do
    require 'socket'

    host     = ENV.fetch('ASTERISK_AMI_HOST', '127.0.0.1')
    port     = ENV.fetch('ASTERISK_AMI_PORT', '5038').to_i
    username = ENV.fetch('ASTERISK_AMI_USER', 'procol-backend')
    secret   = ENV.fetch('ASTERISK_AMI_SECRET') { raise 'ASTERISK_AMI_SECRET no configurado' }

    Rails.logger.info('[AMI] Iniciando listener...')

    loop do
      begin
        socket = TCPSocket.new(host, port)
        socket.gets # banner: "Asterisk Call Manager/x.y\r\n"

        socket.write("Action: Login\r\nUsername: #{username}\r\nSecret: #{secret}\r\n\r\n")

        Rails.logger.info('[AMI] Conectado y autenticado')

        current_event = {}

        while (line = socket.gets)
          line = line.chomp

          if line.empty?
            handle_ami_event(current_event) if current_event.any?
            current_event = {}
          else
            key, value = line.split(': ', 2)
            current_event[key] = value if key && value
          end
        end

        Rails.logger.warn('[AMI] Conexión cerrada por el servidor')
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError => e
        Rails.logger.error("[AMI] Conexión fallida: #{e.message} — reintentando en 10s")
        sleep 10
      rescue StandardError => e
        Rails.logger.error("[AMI] Error inesperado: #{e.message} — reintentando en 5s")
        sleep 5
      ensure
        socket&.close rescue nil
      end
    end
  end
end

def handle_ami_event(event)
  return unless event['Event'] == 'Newchannel'

  channel = event['Channel'].to_s
  exten   = event['Exten'].to_s

  # Solo canales PJSIP/SIP entrantes a extensiones numéricas reales
  return unless channel.match?(/\A(PJSIP|SIP)\//i)
  return if exten.blank? || exten == 's' || exten.match?(/\Avmbl/i)

  caller_id   = event['CallerIDNum'].to_s
  caller_name = event['CallerIDName'].to_s.presence || caller_id

  Rails.logger.info("[AMI] Newchannel exten=#{exten} caller=#{caller_id} channel=#{channel}")

  identity = SipIdentity.find_by(sip_extension: exten)
  unless identity
    Rails.logger.debug("[AMI] Sin SipIdentity para exten=#{exten}")
    return
  end

  Sip::FcmPushService.send_incoming_call(
    identity:    identity,
    caller_id:   caller_id,
    caller_name: caller_name
  )
rescue StandardError => e
  Rails.logger.error("[AMI] handle_ami_event error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
end

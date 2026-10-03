# Corre el fetch_eventos_radian de un conector y hace upsert contra
# Cartera::EventoRadian, idempotente por (account, factura, tipo_evento).
# Mismo principio que SyncService: nunca llama nada fuera del conector.
class Cartera::RadianSyncService
  Resultado = Struct.new(:registros_procesados, :errores, keyword_init: true)

  def initialize(account)
    @account = account
  end

  def run(connector)
    errores = []
    registros_procesados = connector.fetch_eventos_radian.sum { |evento| procesar_evento(evento, errores) }

    Rails.logger.warn("Cartera::RadianSyncService account=#{@account.id}: #{errores.size} error(es).") if errores.any?
    Resultado.new(registros_procesados: registros_procesados, errores: errores)
  end

  private

  def procesar_evento(evento, errores)
    factura = Cartera::Factura.find_by(account: @account, external_id: evento[:factura_external_id])
    unless factura
      errores << "evento RADIAN sin factura conocida: #{evento[:factura_external_id]}"
      return 0
    end

    evento_radian = Cartera::EventoRadian.find_or_initialize_by(account: @account, factura: factura, tipo_evento: evento[:tipo_evento])
    evento_radian.assign_attributes(fecha: evento[:fecha], fuente: evento[:fuente])
    evento_radian.save!
    1
  rescue StandardError => e
    errores << "evento RADIAN #{evento[:factura_external_id]}/#{evento[:tipo_evento]}: #{e.message}"
    0
  end
end

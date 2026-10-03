# Corre un Cartera::ErpConnector, hace upsert idempotente por
# (account, external_id) y deja registro de la corrida en
# Cartera::CorridaSync. Nunca llama nada fuera del conector - como esa clase
# no declara escritura, "cero escritura al ERP" es automatico aqui tambien.
#
# Idempotencia de saldos: una nota credito o un pago solo afectan el saldo de
# la factura la PRIMERA vez que se ven (se detecta por existencia previa del
# external_id); una corrida repetida con los mismos datos nunca vuelve a
# descontar el mismo valor dos veces.
#
# rubocop:disable Metrics/ClassLength -- puerto fiel de sync.service.ts (upsert de 6 entidades);
# fragmentar mas dispersaria un solo algoritmo cohesivo entre varios archivos.
class Cartera::SyncService
  Resultado = Struct.new(:corrida_id, :estado, :registros_procesados, :errores, keyword_init: true)

  def initialize(account)
    @account = account
    @aplicador = Cartera::PagoAplicador.new(account)
  end

  def run(conector_nombre, connector)
    corrida = crear_corrida(conector_nombre)
    errores = []
    registros_procesados = ejecutar_sincronizacion(connector, errores)
    finalizar_corrida(corrida, errores, registros_procesados)
  end

  private

  def crear_corrida(conector_nombre)
    Cartera::CorridaSync.create!(account: @account, conector: conector_nombre, inicio: Time.current, estado: 'en_progreso')
  end

  def ejecutar_sincronizacion(connector, errores)
    cliente_id_by_external_id = {}
    factura_id_by_external_id = {}
    registros_procesados = 0

    begin
      datos = cargar_datos(connector)
      registros_procesados += sincronizar_clientes(datos[:clientes], cliente_id_by_external_id, errores)
      sincronizar_cupos(datos[:cupos], cliente_id_by_external_id, errores)
      registros_procesados += sincronizar_facturas(datos[:facturas], cliente_id_by_external_id, factura_id_by_external_id, errores)
      registros_procesados += sincronizar_notas_credito(datos[:notas_credito], factura_id_by_external_id, errores)
      registros_procesados += sincronizar_pagos(datos[:pagos], cliente_id_by_external_id, factura_id_by_external_id, errores)
      registros_procesados += sincronizar_anticipos(datos[:anticipos], cliente_id_by_external_id, errores)
    rescue StandardError => e
      errores << "corrida interrumpida: #{e.message}"
    end

    registros_procesados
  end

  def cargar_datos(connector)
    {
      clientes: connector.fetch_clientes,
      cupos: connector.fetch_cupos,
      facturas: connector.fetch_facturas,
      notas_credito: connector.fetch_notas_credito,
      pagos: connector.fetch_pagos,
      anticipos: connector.fetch_anticipos
    }
  end

  def finalizar_corrida(corrida, errores, registros_procesados)
    estado = if errores.empty?
               'exitosa'
             elsif registros_procesados.positive?
               'con_errores'
             else
               'fallida'
             end

    corrida.update!(fin: Time.current, estado: estado, registros_procesados: registros_procesados, errores: errores.presence)
    Rails.logger.warn("Cartera::SyncService corrida=#{corrida.id}: #{errores.size} error(es).") if errores.any?

    Resultado.new(corrida_id: corrida.id, estado: estado, registros_procesados: registros_procesados, errores: errores)
  end

  def sincronizar_clientes(clientes, cliente_id_by_external_id, errores)
    procesados = 0
    clientes.each do |cliente_externo|
      cliente = Cartera::Cliente.find_or_initialize_by(account: @account, external_id: cliente_externo[:external_id])
      cliente.assign_attributes(
        tipo_deudor: cliente_externo[:tipo_deudor],
        identificacion: cliente_externo[:identificacion],
        nombre: cliente_externo[:nombre],
        email: cliente_externo[:email],
        telefono: cliente_externo[:telefono],
        sucursal: cliente_externo[:sucursal]
      )
      cliente.save!
      cliente_id_by_external_id[cliente_externo[:external_id]] = cliente.id
      procesados += 1
    rescue StandardError => e
      errores << "cliente #{cliente_externo[:external_id]}: #{e.message}"
    end
    procesados
  end

  def sincronizar_cupos(cupos, cliente_id_by_external_id, errores)
    cupos.each do |cupo|
      cliente_id = cliente_id_by_external_id[cupo[:cliente_external_id]]
      unless cliente_id
        errores << "cupo sin cliente conocido: #{cupo[:cliente_external_id]}"
        next
      end

      # rubocop:disable Rails/SkipsModelValidations -- actualizacion puntual de un solo campo numerico, sin reglas de validacion relevantes
      Cartera::Cliente.where(id: cliente_id).update_all(cupo_asignado: cupo[:cupo_asignado])
      # rubocop:enable Rails/SkipsModelValidations
    rescue StandardError => e
      errores << "cupo #{cupo[:cliente_external_id]}: #{e.message}"
    end
  end

  def sincronizar_facturas(facturas, cliente_id_by_external_id, factura_id_by_external_id, errores)
    procesados = 0
    facturas.each do |factura_externa|
      cliente_id = cliente_id_by_external_id[factura_externa[:cliente_external_id]]
      unless cliente_id
        errores << "factura sin cliente conocido: #{factura_externa[:external_id]}"
        next
      end

      factura_id_by_external_id[factura_externa[:external_id]] = upsert_factura(cliente_id, factura_externa).id
      procesados += 1
    rescue StandardError => e
      errores << "factura #{factura_externa[:external_id]}: #{e.message}"
    end
    procesados
  end

  def upsert_factura(cliente_id, factura_externa)
    factura = Cartera::Factura.find_by(account: @account, external_id: factura_externa[:external_id])
    atributos = {
      numero: factura_externa[:numero], cufe: factura_externa[:cufe],
      fecha_emision: factura_externa[:fecha_emision], fecha_vencimiento: factura_externa[:fecha_vencimiento],
      valor_total: factura_externa[:valor_total]
    }

    if factura
      factura.update!(atributos)
      factura
    else
      Cartera::Factura.create!(
        account: @account, cliente_id: cliente_id, external_id: factura_externa[:external_id],
        saldo_pendiente: factura_externa[:valor_total], **atributos
      )
    end
  end

  def sincronizar_notas_credito(notas_credito, factura_id_by_external_id, errores)
    procesados = 0
    notas_credito.each do |nota|
      factura_id = factura_id_by_external_id[nota[:factura_external_id]]
      unless factura_id
        errores << "nota credito sin factura conocida: #{nota[:external_id]}"
        next
      end
      next if Cartera::NotaCredito.exists?(account: @account, external_id: nota[:external_id]) # ya aplicada antes.

      Cartera::NotaCredito.create!(
        account: @account, factura_id: factura_id, external_id: nota[:external_id],
        valor: nota[:valor], fecha: nota[:fecha], motivo: nota[:motivo]
      )
      @aplicador.decrementar_saldo(factura_id, nota[:valor])
      procesados += 1
    rescue StandardError => e
      errores << "nota credito #{nota[:external_id]}: #{e.message}"
    end
    procesados
  end

  def sincronizar_pagos(pagos, cliente_id_by_external_id, factura_id_by_external_id, errores)
    procesados = 0
    pagos.each do |pago_externo|
      cliente_id = cliente_id_by_external_id[pago_externo[:cliente_external_id]]
      unless cliente_id
        errores << "pago sin cliente conocido: #{pago_externo[:external_id]}"
        next
      end
      next if Cartera::Pago.exists?(account: @account, external_id: pago_externo[:external_id]) # ya aplicado antes.

      crear_y_aplicar_pago(cliente_id, pago_externo, factura_id_by_external_id)
      procesados += 1
    rescue StandardError => e
      errores << "pago #{pago_externo[:external_id]}: #{e.message}"
    end
    procesados
  end

  def crear_y_aplicar_pago(cliente_id, pago_externo, factura_id_by_external_id)
    pago = Cartera::Pago.create!(
      account: @account, cliente_id: cliente_id, external_id: pago_externo[:external_id],
      fecha: pago_externo[:fecha], valor: pago_externo[:valor], medio_pago: pago_externo[:medio_pago]
    )
    factura_conocida = pago_externo[:factura_external_id] && factura_id_by_external_id[pago_externo[:factura_external_id]]

    if factura_conocida
      @aplicador.aplicar_a_factura(cliente_id, pago.id, factura_conocida, pago_externo[:valor])
    else
      @aplicador.aplicar_fifo(cliente_id, pago.id, pago_externo[:valor])
    end
  end

  def sincronizar_anticipos(anticipos, cliente_id_by_external_id, errores)
    procesados = 0
    anticipos.each do |anticipo|
      cliente_id = cliente_id_by_external_id[anticipo[:cliente_external_id]]
      unless cliente_id
        errores << "anticipo sin cliente conocido: #{anticipo[:external_id]}"
        next
      end
      next if Cartera::Pago.exists?(account: @account, external_id: anticipo[:external_id]) # nunca se aplica, pero tampoco se duplica.

      Cartera::Pago.create!(
        account: @account, cliente_id: cliente_id, external_id: anticipo[:external_id],
        fecha: anticipo[:fecha], valor: anticipo[:valor], medio_pago: 'anticipo'
      )
      procesados += 1
    rescue StandardError => e
      errores << "anticipo #{anticipo[:external_id]}: #{e.message}"
    end
    procesados
  end
end
# rubocop:enable Metrics/ClassLength

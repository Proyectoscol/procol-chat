# Conector real contra la API de Alegra (Basic Auth: email + token).
#
# Mapeo confirmado contra una respuesta real de Alegra (ver
# alegra-connector.ts en procol-cartera para el detalle linea por linea):
# - Solo facturas status in (open, closed) cuentan - draft/void se excluyen.
# - fetch_cupos: contacts[].creditLimit.
# - fetch_facturas: numberTemplate.fullNumber, stamp.cufe.
# - fetch_pagos: cada factura trae su payments[] embebido, CON el id de la
#   factura (factura_external_id) - nunca FIFO adivinado para Alegra.
# - fetch_notas_credito: GET /credit-notes + las retenciones de cada factura
#   (invoice.retentions[]) sintetizadas con el mismo contrato.
# - fetch_anticipos: sin resource equivalente en la API - vacio.
# - fetch_eventos_radian: extension sobre el contrato formal - Alegra trae
#   los eventos RADIAN en la misma respuesta de /invoices
#   (fields=events,payments,retentions), sin llamada HTTP aparte.
class Cartera::AlegraConnector < Cartera::ErpConnector
  ESTADOS_FACTURA_VALIDOS = %w[open closed].freeze
  ESTADOS_NOTA_CREDITO_INVALIDOS = %w[draft void].freeze

  # Catalogo de tipos de nota credito para Colombia (developer.alegra.com/
  # reference/colombia) - para mostrar un motivo legible en vez del codigo.
  ETIQUETA_TIPO_NOTA_CREDITO = {
    'PARTIALL_DEVOLUTION' => 'Devolución de parte de los bienes/servicio',
    'VOID_ELECTRONIC_INVOICE' => 'Anulación de factura electrónica',
    'REDUCTION_DISCOUNT_PARTIAL_TOTAL' => 'Rebaja o descuento parcial o total',
    'PRICE_ADJUSTMENT' => 'Ajuste de precio',
    'OTHER' => 'Otro'
  }.freeze

  # events[].type === "CLIENT_ACCEPTANCE" -> evento RADIAN. El otro tipo
  # documentado, CLIENT_EMAILS (SENT/DELIVERED/OPENED/...), no es RADIAN.
  ESTADO_ALEGRA_A_EVENTO_RADIAN = {
    'ACKNOWLEDGMENT_DIAN' => :evento_030,
    'REJECTED_DIAN' => :evento_031,
    'SERVICE_CONFIRMATION' => :evento_032,
    'ACCEPTED_DIAN' => :evento_033,
    'TACITLY_ACCEPTED' => :evento_034
  }.freeze

  def initialize(email:, token:)
    super()
    @client = Cartera::Alegra::ApiClient.new(email: email, token: token)
  end

  def fetch_clientes
    contactos_crudos.map { |contacto| mapear_contacto(contacto) }
  end

  def fetch_cupos
    contactos_crudos
      .select { |contacto| contacto['creditLimit'].to_f.positive? }
      .map { |contacto| { cliente_external_id: contacto['id'].to_s, cupo_asignado: contacto['creditLimit'].to_f } }
  end

  def fetch_facturas
    facturas_validas.map { |factura| mapear_factura(factura) }
  end

  # Un mismo pago de Alegra puede repartirse entre varias facturas - cuando
  # eso pasa, el pago aparece bajo cada factura con un amount DISTINTO (la
  # porcion aplicada a esa factura, no el monto total). external_id combina
  # ambos ids para que siga siendo unico y estable entre corridas.
  def fetch_pagos
    facturas_validas.flat_map do |factura|
      cliente_external_id = factura.dig('client', 'id').to_s
      (factura['payments'] || []).map do |pago|
        {
          external_id: "#{pago['id']}:#{factura['id']}",
          cliente_external_id: cliente_external_id,
          factura_external_id: factura['id'].to_s,
          fecha: Time.zone.parse(pago['date'].to_s),
          valor: pago['amount'].to_f,
          medio_pago: pago['paymentMethod']
        }
      end
    end
  end

  def fetch_anticipos
    []
  end

  def fetch_notas_credito
    reales = @client.paginar('/credit-notes')
                    .reject { |nota| ESTADOS_NOTA_CREDITO_INVALIDOS.include?(nota['status']) }
                    .map { |nota| mapear_nota_credito(nota) }

    reales + retenciones_como_notas_credito
  end

  def fetch_eventos_radian
    facturas_validas.flat_map do |factura|
      factura_external_id = factura['id'].to_s
      (factura['events'] || []).filter_map { |evento| mapear_evento_radian(evento, factura_external_id) }
    end
  end

  private

  # Memoiza la paginacion de /invoices dentro de la misma corrida de sync -
  # fetch_facturas/fetch_pagos/fetch_notas_credito/fetch_eventos_radian leen
  # la misma data cruda sin duplicar llamadas HTTP.
  def facturas_crudas
    @facturas_crudas ||= @client.paginar('/invoices', {
                                           order_field: 'id',
                                           order_direction: 'ASC',
                                           fields: 'events,payments,retentions'
                                         })
  end

  def facturas_validas
    facturas_crudas.select { |factura| ESTADOS_FACTURA_VALIDOS.include?(factura['status']) }
  end

  def contactos_crudos
    @contactos_crudos ||= @client.paginar('/contacts', { type: 'client' })
  end

  def retenciones_como_notas_credito
    facturas_validas.flat_map do |factura|
      (factura['retentions'] || []).map do |retencion|
        {
          external_id: "retencion:#{factura['id']}:#{retencion['id']}",
          factura_external_id: factura['id'].to_s,
          valor: retencion['amount'].to_f,
          fecha: Time.zone.parse(factura['date'].to_s),
          motivo: "Retención #{retencion['name']}".strip
        }
      end
    end
  end

  def mapear_contacto(contacto)
    direccion = contacto['address'] || {}
    {
      external_id: contacto['id'].to_s,
      tipo_deudor: contacto['kindOfPerson'] == 'PERSON_ENTITY' ? :persona_natural : :empresa,
      identificacion: contacto['identification'].to_s,
      nombre: contacto['name'].to_s,
      email: contacto['email'],
      telefono: contacto['phonePrimary'] || contacto['mobile'],
      sucursal: direccion['department']
    }
  end

  def mapear_factura(factura)
    cliente = factura['client'] || {}
    numero_template = factura['numberTemplate'] || {}
    stamp = factura['stamp'] || {}
    {
      external_id: factura['id'].to_s,
      cliente_external_id: cliente['id'].to_s,
      numero: numero_template['fullNumber'] || "#{numero_template['prefix']}#{numero_template['number'] || factura['id']}",
      cufe: stamp['cufe'],
      fecha_emision: Time.zone.parse(factura['date'].to_s),
      fecha_vencimiento: Time.zone.parse((factura['dueDate'] || factura['date']).to_s),
      valor_total: factura['total'].to_f
    }
  end

  def mapear_nota_credito(nota)
    factura_asociada = (nota['invoices'] || []).first || {}
    tipo = nota['type']
    {
      external_id: nota['id'].to_s,
      factura_external_id: factura_asociada['id'].to_s,
      valor: nota['total'].to_f,
      fecha: Time.zone.parse(nota['date'].to_s),
      motivo: ETIQUETA_TIPO_NOTA_CREDITO[tipo] || nota['observations'] || tipo
    }
  end

  def mapear_evento_radian(evento, factura_external_id)
    return nil unless evento['type'] == 'CLIENT_ACCEPTANCE'

    tipo_evento = ESTADO_ALEGRA_A_EVENTO_RADIAN[evento['status']]
    return nil unless tipo_evento

    {
      factura_external_id: factura_external_id,
      tipo_evento: tipo_evento,
      fecha: Time.zone.parse(evento['date'].to_s),
      fuente: 'alegra'
    }
  end
end

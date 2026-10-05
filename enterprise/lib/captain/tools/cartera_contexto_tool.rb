# Da al asistente el contexto de cartera del contacto de esta conversacion:
# facturas abiertas, saldo/score, y los envios de campana recientes con sus
# facturas y resultado. Esto es lo que le permite distinguir "ya pago lo
# que prometio en enero" de "esta es una factura nueva de abril" cuando el
# cliente responde a un mensaje de cobro.
class Captain::Tools::CarteraContextoTool < Captain::Tools::BasePublicTool
  description 'Get accounts-receivable (cartera) context for the contact in this conversation: open invoices, ' \
              'balance, risk score, and recent collection campaign sends with their outcomes'

  def perform(tool_context, **)
    contact = find_contact(tool_context.state)
    return 'Contact not found' unless contact

    cliente = account_scoped(Cartera::Cliente).find_by(contact_id: contact.id)
    return 'This contact is not a cartera (accounts receivable) client.' unless cliente

    log_tool_usage('cartera_contexto', { contact_id: contact.id, cliente_id: cliente.id })

    [resumen_caso(cliente), facturas_abiertas(cliente), envios_recientes(cliente)].join("\n\n")
  end

  private

  def resumen_caso(cliente)
    caso = cliente.caso
    return "# Cartera\nCliente #{cliente.nombre} sin saldo abierto actualmente." if caso.nil?

    <<~TEXT
      # Cartera
      Cliente: #{cliente.nombre} (#{cliente.identificacion})
      Saldo abierto: #{caso.saldo_abierto}
      Tramo de mora: #{caso.tramo || 'sin mora'} (#{caso.dias_vencido_max || 0} dias)
      Puntaje de riesgo: #{caso.puntaje_riesgo || 'sin calcular'} / Score credito: #{caso.score_credito || 'sin calcular'}
      No cobrar: #{caso.no_cobrar ? "si (#{caso.razon_no_cobrar})" : 'no'}
    TEXT
  end

  def facturas_abiertas(cliente)
    facturas = cliente.facturas.where('saldo_pendiente > 0').order(:fecha_vencimiento)
    return "# Facturas abiertas\nNinguna." if facturas.empty?

    lineas = facturas.map { |f| "- #{f.numero}: saldo #{f.saldo_pendiente}, vence #{f.fecha_vencimiento.to_date}" }
    "# Facturas abiertas\n#{lineas.join("\n")}"
  end

  # Las facturas de un envio anterior pueden ser DISTINTAS a las abiertas
  # hoy - por eso cada linea lista sus propias factura_ids, no las de arriba.
  def envios_recientes(cliente)
    scope = cliente.account.cartera_envios.where(cliente_id: cliente.id).where.not(estado: 'programado')
    envios = scope.order(created_at: :desc).limit(10)
    return "# Envios de campana recientes\nNinguno." if envios.empty?

    "# Envios de campana recientes\n#{envios.map { |e| resumen_envio(e) }.join("\n")}"
  end

  def resumen_envio(envio)
    "- #{envio.created_at.to_date} (#{envio.canal}): facturas #{envio.factura_ids.join(', ')}, " \
      "estado=#{envio.estado}, resultado=#{envio.resultado || 'sin resultado'}"
  end

  def permissions
    []
  end
end

# Aplica un pago a una o varias facturas de un cliente, decrementando
# saldo_pendiente. Extraido de Cartera::SyncService porque es un concern
# propio (aplicacion de pagos) distinto de "traer datos del conector".
class Cartera::PagoAplicador
  def initialize(account)
    @account = account
  end

  # Aplica a la factura especifica que el conector de origen ya identifico
  # (ej. Alegra). Si sobra saldo del pago, el resto cae a FIFO sobre las
  # demas facturas abiertas del cliente.
  def aplicar_a_factura(cliente_id, pago_id, factura_id, monto_disponible)
    factura = Cartera::Factura.find_by(id: factura_id)
    saldo = factura ? factura.saldo_pendiente.to_f : 0.0
    aplicar = saldo.clamp(0.0, monto_disponible)

    if aplicar.positive?
      Cartera::AplicacionPago.create!(account: @account, pago_id: pago_id, factura_id: factura_id, valor_aplicado: aplicar)
      decrementar_saldo(factura_id, aplicar)
    end

    restante = monto_disponible - aplicar
    aplicar_fifo(cliente_id, pago_id, restante) if restante.positive?
  end

  # Heuristica FIFO: solo se usa cuando el conector de origen no sabe a que
  # factura especifica se aplico un pago - aplica a las facturas abiertas del
  # cliente, la mas antigua primero.
  def aplicar_fifo(cliente_id, pago_id, monto_disponible)
    restante = monto_disponible
    facturas_abiertas(cliente_id).each do |factura|
      break if restante <= 0

      aplicar = [factura.saldo_pendiente.to_f, restante].min
      next if aplicar <= 0

      Cartera::AplicacionPago.create!(account: @account, pago_id: pago_id, factura_id: factura.id, valor_aplicado: aplicar)
      decrementar_saldo(factura.id, aplicar)
      restante -= aplicar
    end
  end

  def decrementar_saldo(factura_id, valor)
    # rubocop:disable Rails/SkipsModelValidations -- decremento atomico a nivel SQL, equivalente a Prisma {decrement: valor}
    Cartera::Factura.where(id: factura_id).update_all(['saldo_pendiente = saldo_pendiente - ?', valor])
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

  def facturas_abiertas(cliente_id)
    Cartera::Factura.where(account: @account, cliente_id: cliente_id)
                    .where('saldo_pendiente > 0')
                    .order(fecha_vencimiento: :asc)
  end
end

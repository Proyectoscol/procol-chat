# Compara las dos fotografias mas recientes de un cliente (ver
# Cartera::SnapshotService) para responder "que paso con este cliente desde
# la ultima foto": cambio de saldo, pagos registrados en el periodo,
# facturas nuevas emitidas en el periodo, y si cambio de tramo de mora. Es
# la pieza que permite medir el efecto real de una campana (no solo si
# contesto, si efectivamente pago) sin acoplarse a ninguna campana en
# particular - cualquier cliente con al menos dos fotos puede compararse.
class Cartera::ComparacionSnapshotsService
  pattr_initialize [:cliente!]

  def call
    return sin_datos_suficientes if snapshots.size < 2

    { disponible: true }.merge(fechas).merge(saldos).merge(tramos).merge(movimientos_en_periodo)
  end

  private

  def fechas
    { fecha_anterior: anterior.fecha_snapshot, fecha_actual: actual.fecha_snapshot }
  end

  def saldos
    saldo_anterior = actual_f(anterior.saldo_abierto)
    saldo_actual = actual_f(actual.saldo_abierto)
    { saldo_anterior: saldo_anterior, saldo_actual: saldo_actual, cambio_saldo: saldo_actual - saldo_anterior }
  end

  def tramos
    { tramo_anterior: anterior.tramo, tramo_actual: actual.tramo, cambio_tramo: anterior.tramo != actual.tramo }
  end

  def movimientos_en_periodo
    { pagos_en_periodo: pagos_en_periodo, facturas_nuevas_en_periodo: facturas_nuevas_en_periodo }
  end

  def snapshots
    @snapshots ||= cliente.snapshots.limit(2)
  end

  def actual
    snapshots.first
  end

  def anterior
    snapshots.second
  end

  def actual_f(valor)
    valor.to_f
  end

  def pagos_en_periodo
    cliente.pagos.where(fecha: anterior.fecha_snapshot..actual.fecha_snapshot).sum(:valor).to_f
  end

  def facturas_nuevas_en_periodo
    cliente.facturas.where(fecha_emision: anterior.fecha_snapshot..actual.fecha_snapshot).count
  end

  def sin_datos_suficientes
    { disponible: false }
  end
end

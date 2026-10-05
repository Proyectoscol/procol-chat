# Fotografia el estado actual de cartera_casos de cada cliente de la cuenta
# hacia cartera_snapshots_cliente - no calcula nada, solo copia lo que
# Cartera::PriorizacionService ya dejo en cada Cartera::Caso. Pensado para
# correr cada dos semanas (ver config/schedule.yml); idempotente dentro del
# mismo dia gracias al indice unico (account_id, cliente_id, fecha_snapshot)
# en la migracion - find_or_create_by evita el error de duplicado si el job
# se reintenta.
class Cartera::SnapshotService
  pattr_initialize [:account!]

  def call
    fecha = Time.current
    creados = 0

    account.cartera_casos.includes(:cliente).find_each do |caso|
      creados += 1 if tomar_foto(caso, fecha)
    end

    { snapshots_creados: creados }
  end

  private

  def tomar_foto(caso, fecha)
    snapshot = account.cartera_snapshots_cliente.find_or_initialize_by(
      cliente_id: caso.cliente_id, fecha_snapshot: fecha.to_date.to_time
    )
    return false if snapshot.persisted?

    snapshot.assign_attributes(
      saldo_abierto: caso.saldo_abierto, tramo: caso.tramo, dias_vencido_max: caso.dias_vencido_max,
      puntaje_riesgo: caso.puntaje_riesgo, score_credito: caso.score_credito,
      facturas_abiertas_cantidad: caso.facturas_abiertas_cantidad,
      total_facturado_historico: caso.total_facturado_historico,
      no_cobrar: caso.no_cobrar, nivel_escalamiento: caso.nivel_escalamiento
    )
    snapshot.save!
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end

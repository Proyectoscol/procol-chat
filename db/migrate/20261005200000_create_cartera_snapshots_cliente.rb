# Fotografia periodica del estado de cartera de un cliente (saldo, tramo,
# puntaje, etc.), independiente de si se le envio algo o no - a diferencia
# de cartera_envios.*_al_enviar (foto atada a un envio puntual), esto es una
# foto de TODO el portafolio de un cliente en un punto en el tiempo, para
# poder comparar "como estaba hace dos semanas" vs "como esta ahora" y medir
# si una campana de cobro tuvo efecto real (el cliente pago) y no solo si
# contesto.
#
# Las columnas replican exactamente lo que Cartera::PriorizacionService ya
# calcula hoy en cartera_casos - no hay ningun calculo nuevo aqui, solo una
# copia periodica.
class CreateCarteraSnapshotsCliente < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_snapshots_cliente do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :cliente, null: false, foreign_key: { to_table: :cartera_clientes, on_delete: :cascade }
      t.datetime :fecha_snapshot, null: false
      t.decimal :saldo_abierto, precision: 18, scale: 2
      t.string :tramo
      t.integer :dias_vencido_max
      t.integer :puntaje_riesgo
      t.integer :score_credito
      t.integer :facturas_abiertas_cantidad
      t.decimal :total_facturado_historico, precision: 18, scale: 2
      t.boolean :no_cobrar, null: false, default: false
      t.string :nivel_escalamiento

      t.timestamps
    end

    add_index :cartera_snapshots_cliente, [:account_id, :cliente_id, :fecha_snapshot],
              unique: true, name: 'idx_snapshots_cliente_unico_por_fecha'
  end
end

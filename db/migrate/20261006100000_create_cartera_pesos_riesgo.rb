# Pesos del algoritmo de puntaje de riesgo unificado (Cartera::
# PuntajeRiesgoService) - una fila por cuenta, editable desde Ajustes >
# Pesos del algoritmo. Antes de esto existian DOS formulas de puntaje
# distintas con pesos escritos como constantes Ruby
# (PriorizacionService::PESOS_DEFAULT para prioridad_score,
# PerfilPagoService#calcular_puntaje_riesgo con pesos hardcoded inline para
# puntaje_riesgo) que podian estar en desacuerdo sobre que tan riesgoso es
# un cliente - esta tabla es la base para unificarlas en un solo puntaje
# configurable en tiempo real, mismo patron que cartera_tarifas_mensajeria.
#
# Los defaults de columna son el punto de partida sugerido (ver plan de
# fase 3): mora actual 20%, pagos tardios 25%, saldo abierto 20%, cupo
# utilizado 10%, antiguedad de la relacion 10%, % cartera vencida 10%,
# total facturado historico 5% - deben sumar 100% (validado en el modelo).
class CreateCarteraPesosRiesgo < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_pesos_riesgo do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.decimal :mora_actual, precision: 5, scale: 4, null: false, default: 0.20
      t.decimal :pagos_tardios, precision: 5, scale: 4, null: false, default: 0.25
      t.decimal :saldo_abierto, precision: 5, scale: 4, null: false, default: 0.20
      t.decimal :cupo_utilizado, precision: 5, scale: 4, null: false, default: 0.10
      t.decimal :antiguedad_relacion, precision: 5, scale: 4, null: false, default: 0.10
      t.decimal :cartera_vencida_pct, precision: 5, scale: 4, null: false, default: 0.10
      t.decimal :total_facturado, precision: 5, scale: 4, null: false, default: 0.05

      t.timestamps
    end
  end
end

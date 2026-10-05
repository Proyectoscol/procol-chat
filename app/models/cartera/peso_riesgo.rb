# Pesos del algoritmo de puntaje de riesgo unificado (ver
# Cartera::PuntajeRiesgoService) - una fila por cuenta, editable desde
# Ajustes > Pesos del algoritmo. Si la cuenta aun no ha guardado ninguno,
# .para(account) devuelve un registro nuevo sin persistir con los defaults
# de columna (ver migracion) - leer los pesos nunca crea la fila.
class Cartera::PesoRiesgo < ApplicationRecord
  self.table_name = 'cartera_pesos_riesgo'

  FACTORES = %i[mora_actual pagos_tardios saldo_abierto cupo_utilizado antiguedad_relacion cartera_vencida_pct total_facturado].freeze
  SUMA_ESPERADA = 1.0
  TOLERANCIA_SUMA = 0.001

  belongs_to :account

  validates :account_id, uniqueness: true
  validates :mora_actual, :pagos_tardios, :saldo_abierto, :cupo_utilizado, :antiguedad_relacion, :cartera_vencida_pct, :total_facturado,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validate :pesos_suman_uno

  def self.para(account)
    account.cartera_peso_riesgo || new(account: account)
  end

  private

  def pesos_suman_uno
    suma = FACTORES.sum { |factor| public_send(factor).to_f }
    return if (suma - SUMA_ESPERADA).abs <= TOLERANCIA_SUMA

    errors.add(:base, "Los pesos deben sumar 100% (suman #{(suma * 100).round(1)}%).")
  end
end

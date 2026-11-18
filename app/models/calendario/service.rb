# == Schema Information
#
# Table name: calendario_services
#
#  id                :bigint           not null, primary key
#  active            :boolean          default(TRUE), not null
#  base_price        :integer
#  color             :string
#  duration_minutes  :integer          not null
#  included_sessions :integer          default(0), not null
#  kind              :integer          default("consultation"), not null
#  name              :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_calendario_services_on_account_and_name  (account_id,name) UNIQUE
#  index_calendario_services_on_account_id        (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Calendario::Service < ApplicationRecord
  self.table_name = 'calendario_services'

  enum :kind, { consultation: 0, control: 1, procedure: 2 }

  belongs_to :account
  has_many :service_professionals, class_name: 'Calendario::ServiceProfessional', dependent: :destroy
  has_many :professionals, through: :service_professionals, class_name: 'Calendario::Professional'
  has_many :appointments, class_name: 'Calendario::Appointment', dependent: :destroy
  has_many :prices, class_name: 'Calendario::ServicePrice', dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }
  validates :included_sessions, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :base_price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active, -> { where(active: true) }

  # El control/seguimiento solo tiene sentido si el contacto ya tuvo una
  # consulta o procedimiento -- no existe un control "de entrada".
  def requires_prior_visit?
    control?
  end

  # prices.to_a (en vez de find_by dos veces) carga la coleccion completa UNA
  # sola vez y la deja en memoria en la instancia -- como appointment#price
  # (unico caller) se llama una vez POR CITA en listas de cientos/miles de
  # citas, y las citas de un mismo servicio comparten la misma instancia de
  # Service (gracias a includes(:service)), esto evita 2 queries de mas por
  # cita (encontrado como N+1 real: 1592 citas -> 1092 queries antes de este
  # fix). find_by repetido SI estaba usando la cache de consultas de Rails,
  # pero el overhead de reconstruir el Relation/Arel en Ruby para cada
  # llamada seguia siendo real.
  def price_for(payer)
    loaded_prices = prices.to_a
    specific = payer.present? ? loaded_prices.find { |p| p.payer_id == payer.id } : nil
    specific&.price || loaded_prices.find { |p| p.payer_id.nil? }&.price || base_price
  end
end

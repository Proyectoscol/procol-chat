# == Schema Information
#
# Table name: calendario_service_prices
#
#  id         :bigint           not null, primary key
#  copago     :integer
#  price      :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  payer_id   :bigint
#  service_id :bigint           not null
#
# Indexes
#
#  index_calendario_service_prices_on_payer_id           (payer_id)
#  index_calendario_service_prices_on_service_and_payer  (service_id,payer_id) UNIQUE
#  index_calendario_service_prices_on_service_default    (service_id) UNIQUE WHERE (payer_id IS NULL)
#  index_calendario_service_prices_on_service_id         (service_id)
#
# Foreign Keys
#
#  fk_rails_...  (payer_id => calendario_payers.id) ON DELETE => cascade
#  fk_rails_...  (service_id => calendario_services.id) ON DELETE => cascade
#
class Calendario::ServicePrice < ApplicationRecord
  self.table_name = 'calendario_service_prices'

  belongs_to :service, class_name: 'Calendario::Service'
  belongs_to :payer, class_name: 'Calendario::Payer', optional: true

  validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :copago, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :payer_belongs_to_same_account

  private

  def payer_belongs_to_same_account
    return if payer.blank? || service.blank?
    return if payer.account_id == service.account_id

    errors.add(:payer, :invalid)
  end
end

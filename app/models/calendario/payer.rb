# == Schema Information
#
# Table name: calendario_payers
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  kind       :integer          default("particular"), not null
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_calendario_payers_on_account_and_name  (account_id,name) UNIQUE
#  index_calendario_payers_on_account_id        (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Calendario::Payer < ApplicationRecord
  self.table_name = 'calendario_payers'

  enum :kind, { particular: 0, eps: 1, plan_complementario: 2, prepagada: 3, poliza: 4 }

  belongs_to :account
  has_many :prices, class_name: 'Calendario::ServicePrice', dependent: :destroy
  has_many :contacts, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :active, -> { where(active: true) }
end

# == Schema Information
#
# Table name: calendario_specialties
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_calendario_specialties_on_account_and_name  (account_id,name) UNIQUE
#  index_calendario_specialties_on_account_id        (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Calendario::Specialty < ApplicationRecord
  self.table_name = 'calendario_specialties'

  belongs_to :account
  has_many :professionals, class_name: 'Calendario::Professional', dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }

  scope :active, -> { where(active: true) }
end

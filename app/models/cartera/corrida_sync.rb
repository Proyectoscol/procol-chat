# == Schema Information
#
# Table name: cartera_corridas_sync
#
#  id                   :bigint           not null, primary key
#  conector             :string           not null
#  errores              :jsonb
#  estado               :string           default("en_progreso"), not null
#  fin                  :datetime
#  inicio               :datetime         not null
#  registros_procesados :integer          default(0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#
# Indexes
#
#  index_cartera_corridas_sync_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Cartera::CorridaSync < ApplicationRecord
  self.table_name = 'cartera_corridas_sync'

  belongs_to :account

  validates :conector, :inicio, :estado, presence: true
end

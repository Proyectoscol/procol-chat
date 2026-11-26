# Excepcion puntual al horario laboral normal de un inbox -- pensado para
# festivos colombianos donde SI se trabaja (ej. "este 7 de agosto sí
# atendemos"), aunque tambien sirve al reves (cerrar un dia que normalmente
# seria laboral). `open: true/false` siempre gana sobre lo que diria el
# horario semanal o el calendario de festivos para esa fecha -- ver
# Calendario::BusinessHours.
# == Schema Information
#
# Table name: calendario_working_day_overrides
#
#  id         :bigint           not null, primary key
#  date       :date             not null
#  note       :string
#  open       :boolean          default(TRUE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  inbox_id   :bigint           not null
#
# Indexes
#
#  index_calendario_working_day_overrides_on_account_id         (account_id)
#  index_calendario_working_day_overrides_on_inbox_id           (inbox_id)
#  index_calendario_working_day_overrides_on_inbox_id_and_date  (inbox_id,date) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class Calendario::WorkingDayOverride < ApplicationRecord
  self.table_name = 'calendario_working_day_overrides'

  belongs_to :account
  belongs_to :inbox

  validates :date, presence: true, uniqueness: { scope: :inbox_id }
end

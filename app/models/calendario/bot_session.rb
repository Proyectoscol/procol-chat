# Estado de un triage en curso para una conversacion puntual -- ver
# Calendario::WelcomeBotFlowRunner para la logica que avanza esto paso a
# paso. Cadencia de recordatorio/reset confirmada por el usuario: 2 avisos
# cada 5 min, reset a los 20 min del segundo aviso (ver
# Calendario::BotSessionReminderJob).
class Calendario::BotSession < ApplicationRecord
  self.table_name = 'calendario_bot_sessions'

  STATUSES = %w[active handed_off reset].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :welcome_bot_flow, class_name: 'Calendario::WelcomeBotFlow'

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: 'active') }

  def active?
    status == 'active'
  end

  def current_step_config
    welcome_bot_flow.steps[current_step]
  end
end

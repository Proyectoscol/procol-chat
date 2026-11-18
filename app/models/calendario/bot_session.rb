# Estado de un triage en curso para una conversacion puntual -- ver
# Calendario::WelcomeBotFlowRunner para la logica que avanza esto paso a
# paso. Cadencia confirmada por el usuario: 2 avisos cada 5 min, y si
# tampoco responde al segundo, un mensaje de escalamiento 20 min despues
# que entrega la conversacion a un agente disponible (ver
# Calendario::BotSessionReminderJob).
# == Schema Information
#
# Table name: calendario_bot_sessions
#
#  id                  :bigint           not null, primary key
#  answers             :jsonb            not null
#  current_step        :integer          default(0), not null
#  last_prompted_at    :datetime
#  reminder_count      :integer          default(0), not null
#  status              :string           default("active"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  conversation_id     :bigint           not null
#  welcome_bot_flow_id :bigint           not null
#
# Indexes
#
#  index_calendario_bot_sessions_on_account_id           (account_id)
#  index_calendario_bot_sessions_on_conversation_id      (conversation_id)
#  index_calendario_bot_sessions_on_welcome_bot_flow_id  (welcome_bot_flow_id)
#  index_one_active_bot_session_per_conversation         (conversation_id) UNIQUE WHERE ((status)::text = 'active'::text)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (welcome_bot_flow_id => calendario_welcome_bot_flows.id) ON DELETE => cascade
#
class Calendario::BotSession < ApplicationRecord
  self.table_name = 'calendario_bot_sessions'

  STATUSES = %w[active handed_off].freeze

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

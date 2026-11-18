# Configuracion de un bot de triage: a que texto reacciona (match_type +
# match_value) y que secuencia de preguntas hace. Varios pueden coexistir en
# la misma bandeja -- pedido explicito del usuario: "mas adelante dependiendo
# de lo que la persona escriba quiero enviarle otro bot de triaje [...]
# deben haber la posibilidad de configurarse varios".
#
# steps (jsonb), cada paso:
#   { "ask" => "...", "options" => ["...", "..."], "if" => { "step" => 0, "equals" => "..." } }
# "if" es opcional -- sin el, el paso siempre aplica; con el, solo si la
# respuesta de un paso anterior fue exactamente ese valor (ver
# Calendario::WelcomeBotFlowRunner#applicable_step?).
# == Schema Information
#
# Table name: calendario_welcome_bot_flows
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  escalation_message :text
#  match_type         :string           default("default"), not null
#  match_value        :string
#  name               :string           not null
#  priority           :integer          default(0), not null
#  steps              :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  inbox_id           :bigint           not null
#
# Indexes
#
#  index_calendario_welcome_bot_flows_on_account_id  (account_id)
#  index_calendario_welcome_bot_flows_on_inbox_id    (inbox_id)
#  index_one_active_default_flow_per_inbox           (inbox_id,match_type) UNIQUE WHERE (((match_type)::text = 'default'::text) AND (active = true))
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#
class Calendario::WelcomeBotFlow < ApplicationRecord
  self.table_name = 'calendario_welcome_bot_flows'

  MATCH_TYPES = %w[default keyword].freeze

  belongs_to :account
  belongs_to :inbox
  has_many :bot_sessions, class_name: 'Calendario::BotSession', dependent: :destroy

  validates :name, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES }
  validates :match_value, presence: true, if: :keyword?
  validates :match_value, absence: true, unless: :keyword?
  validate :inbox_belongs_to_account

  scope :active, -> { where(active: true) }

  def keyword?
    match_type == 'keyword'
  end

  def default?
    match_type == 'default'
  end

  # Normaliza igual que Calendario::NoShowReplyListener -- minusculas, sin
  # tildes -- para que "Particular"/"PARTICULAR"/"particular" matcheen igual.
  def self.normalize(text)
    text.to_s.downcase.unicode_normalize(:nfkd).gsub(/[^\x00-\x7F]/, '').strip
  end

  def matches?(text)
    return false unless keyword?

    self.class.normalize(text).include?(self.class.normalize(match_value))
  end

  # El primer keyword que matchea por prioridad (mas alto primero), o el
  # default de la bandeja si ninguno matchea.
  def self.match_for(inbox, text)
    flows = where(inbox: inbox).active.order(priority: :desc)
    flows.find { |flow| flow.keyword? && flow.matches?(text) } ||
      flows.find(&:default?)
  end

  private

  def inbox_belongs_to_account
    return if inbox.blank? || inbox.account_id == account_id

    errors.add(:inbox, :invalid)
  end
end

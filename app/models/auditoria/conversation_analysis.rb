# == Schema Information
#
# Table name: auditoria_conversation_analyses
#
#  id              :bigint           not null, primary key
#  analyzed_at     :datetime
#  results         :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#
# Indexes
#
#  index_auditoria_conversation_analyses_on_account_id       (account_id)
#  index_auditoria_conversation_analyses_on_conversation_id  (conversation_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#
class Auditoria::ConversationAnalysis < ApplicationRecord
  self.table_name = 'auditoria_conversation_analyses'

  belongs_to :account
  belongs_to :conversation

  validates :conversation_id, uniqueness: true
end

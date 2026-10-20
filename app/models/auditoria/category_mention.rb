# == Schema Information
#
# Table name: auditoria_category_mentions
#
#  id              :bigint           not null, primary key
#  occurred_on     :date             not null
#  created_at      :datetime         not null
#  account_id      :bigint           not null
#  category_id     :bigint           not null
#  conversation_id :bigint           not null
#  message_id      :bigint
#
# Indexes
#
#  index_auditoria_category_mentions_on_account_id       (account_id)
#  index_auditoria_category_mentions_on_category_id      (category_id)
#  index_auditoria_category_mentions_on_conversation_id  (conversation_id)
#  index_auditoria_category_mentions_on_message_id       (message_id)
#  index_auditoria_mentions_on_account_category_day      (account_id,category_id,occurred_on)
#  index_auditoria_mentions_on_conv_category_day         (conversation_id,category_id,occurred_on) UNIQUE WHERE (message_id IS NULL)
#  index_auditoria_mentions_on_message_and_category      (message_id,category_id) UNIQUE WHERE (message_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (category_id => auditoria_categories.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (message_id => messages.id) ON DELETE => cascade
#
class Auditoria::CategoryMention < ApplicationRecord
  self.table_name = 'auditoria_category_mentions'

  belongs_to :account
  belongs_to :category, class_name: 'Auditoria::Category'
  belongs_to :conversation
  belongs_to :message, optional: true
end

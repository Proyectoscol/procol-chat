# == Schema Information
#
# Table name: auditoria_advisor_daily_summaries
#
#  id                  :bigint           not null, primary key
#  category_counts     :jsonb            not null
#  conversations_count :integer          default(0), not null
#  feedback_tags       :string           default([]), not null, is an Array
#  generated_at        :datetime
#  results             :jsonb            not null
#  summary_date        :date             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  user_id             :bigint           not null
#
# Indexes
#
#  idx_auditoria_advisor_summary_unique                      (account_id,user_id,summary_date) UNIQUE
#  index_auditoria_advisor_daily_summaries_on_account_id     (account_id)
#  index_auditoria_advisor_daily_summaries_on_feedback_tags  (feedback_tags) USING gin
#  index_auditoria_advisor_daily_summaries_on_user_id        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
# Resumen diario sintetizado por IA del desempeno de un asesor, agregando
# los Auditoria::ConversationAnalysis + Auditoria::CategoryMention de las
# conversaciones que atendio ese dia (ver Auditoria::AdvisorDailyRollupService).
# Un asesor puede trabajar sobre varios inboxes -- este resumen se genera a
# nivel de cuenta completa, nunca por inbox (ver nota en el plan sobre por
# que no se resintetiza por cada vista de admin restringido).
class Auditoria::AdvisorDailySummary < ApplicationRecord
  self.table_name = 'auditoria_advisor_daily_summaries'

  belongs_to :account
  belongs_to :user

  validates :summary_date, uniqueness: { scope: [:account_id, :user_id] }
end

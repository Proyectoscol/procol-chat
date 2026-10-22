# Corre Auditoria::AdvisorDailyRollupService en background por el mismo
# motivo que Auditoria::ConversationAnalyzerJob: la llamada a OpenAI puede
# tardar.
class Auditoria::AdvisorDailyRollupJob < ApplicationJob
  queue_as :low

  def perform(account_id, user_id, summary_date, triggered_by: :batch)
    account = Account.find_by(id: account_id)
    user = User.find_by(id: user_id)
    return unless account && user

    Auditoria::AdvisorDailyRollupService.new(
      account: account, user: user, summary_date: summary_date, triggered_by: triggered_by
    ).perform
  end
end

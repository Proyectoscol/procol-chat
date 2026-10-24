# Corre Auditoria::AdvisorDailyRollupService en background por el mismo
# motivo que Auditoria::ConversationAnalyzerJob: la llamada a OpenAI puede
# tardar.
class Auditoria::AdvisorDailyRollupJob < ApplicationJob
  queue_as :low

  # pipeline_run_kind presente == esta corrida tiene seguimiento de progreso
  # (ver Auditoria::PipelineRunTracker); nil en el cron real.
  def perform(account_id, user_id, summary_date, triggered_by: :batch, pipeline_run_kind: nil)
    account = Account.find_by(id: account_id)
    user = User.find_by(id: user_id)
    return unless account && user

    # Mismo manejo que Auditoria::ConversationAnalyzerJob#perform: sin este
    # rescue, una excepcion no manejada (no un {error:} ya controlado por el
    # service) dejaba el contador de progreso sin tocar para siempre, con la
    # barra trabada por debajo del 100% hasta el TTL de 6h del tracker.
    unexpected_error = nil
    result = begin
      Auditoria::AdvisorDailyRollupService.new(
        account: account, user: user, summary_date: summary_date, triggered_by: triggered_by
      ).perform
    rescue StandardError => e
      unexpected_error = e
      { error: e.message }
    end

    track_progress!(account, pipeline_run_kind, result) if pipeline_run_kind
    raise unexpected_error if unexpected_error
  end

  private

  def track_progress!(account, kind, result)
    if result[:error]
      spend_limited = !Auditoria::AiUsageLogger.within_limit?(account)
      Auditoria::PipelineRunTracker.increment_errored!(account, kind, spend_limited: spend_limited)
    else
      Auditoria::PipelineRunTracker.increment_processed!(account, kind)
    end
  end
end

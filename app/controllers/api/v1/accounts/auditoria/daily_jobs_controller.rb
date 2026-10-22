# Boton de admin en Settings > Integrations > OpenAI > Usage para disparar
# cualquiera de las 2 etapas del pipeline diario (ver app/jobs/auditoria/)
# sin esperar al cron -- util para la primera corrida o para probar un
# cambio de configuracion ya mismo. perform_later (no perform_now) para no
# bloquear el request mientras Sidekiq procesa en background.
class Api::V1::Accounts::Auditoria::DailyJobsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def run_conversation_analysis
    Auditoria::DailyConversationAnalysisSchedulerJob.perform_later(account_id: Current.account.id)
    head :ok
  end

  def run_advisor_rollup
    Auditoria::AdvisorDailyRollupSchedulerJob.perform_later(summary_date: summary_date, account_id: Current.account.id)
    head :ok
  end

  private

  def summary_date
    params[:summary_date].presence ? Date.parse(params[:summary_date]) : Date.yesterday
  end

  def check_authorization
    authorize(:'auditoria/daily_jobs')
  end
end

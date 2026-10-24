# Botones de admin en Settings > Integrations > OpenAI > Usage para
# disparar cualquiera de las 3 corridas del pipeline diario (ver
# app/jobs/auditoria/) sin esperar al cron -- util para la primera corrida
# o para probar un cambio de configuracion ya mismo. perform_later (no
# perform_now) para no bloquear el request mientras Sidekiq procesa en
# background; track_progress: true para que el admin vea el avance en vivo
# (ver Auditoria::PipelineRunTracker), a diferencia del cron real que nunca
# lo activa.
class Api::V1::Accounts::Auditoria::DailyJobsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def run_conversation_analysis
    return render json: { error: 'A run is already in progress' }, status: :conflict if run_in_progress?('conversation_analysis')

    Auditoria::DailyConversationAnalysisSchedulerJob.perform_later(account_id: Current.account.id, track_progress: true)
    head :ok
  end

  def run_advisor_rollup
    return render json: { error: 'Invalid summary_date' }, status: :unprocessable_entity unless summary_date
    return render json: { error: 'A run is already in progress' }, status: :conflict if run_in_progress?('advisor_rollup')

    Auditoria::AdvisorDailyRollupSchedulerJob.perform_later(
      summary_date: summary_date, account_id: Current.account.id, track_progress: true
    )
    head :ok
  end

  def run_full_backlog
    return render json: { error: 'A run is already in progress' }, status: :conflict if run_in_progress?('backlog')

    Auditoria::DailyConversationAnalysisSchedulerJob.perform_later(
      account_id: Current.account.id, unbounded: true, track_progress: true
    )
    head :ok
  end

  def estimate
    return render json: { error: 'Invalid kind' }, status: :unprocessable_entity unless valid_kind?

    render json: Auditoria::ManualRunEstimateService.new(account: Current.account, kind: params[:kind]).call
  end

  def progress
    render json: Auditoria::PipelineRunTracker.status(Current.account, params[:kind])
  end

  private

  # Sin este guard, dos clicks (o dos admins) antes de que termine la
  # primera corrida reinician el contador de Auditoria::PipelineRunTracker a
  # mitad de camino (status overwrite, ver #start!) y pueden encolar el
  # analisis de las mismas conversaciones dos veces -- needs_analysis?
  # compara contra el analisis ya persistido, no contra lo ya encolado, asi
  # que dos corridas casi simultaneas pueden pagarle a OpenAI dos veces por
  # la misma conversacion.
  def run_in_progress?(kind)
    # PipelineRunTracker.status devuelve {status: 'idle'} (symbol) cuando no
    # hay nada en Redis, pero keys STRING (JSON.parse) cuando si hay estado
    # -- with_indifferent_access evita que esto siempre lea nil en el caso
    # mas comun (una corrida real en progreso).
    Auditoria::PipelineRunTracker.status(Current.account, kind).with_indifferent_access[:status] == 'running'
  end

  def valid_kind?
    Auditoria::ManualRunEstimateService::VALID_KINDS.include?(params[:kind])
  end

  def summary_date
    params[:summary_date].presence ? Date.parse(params[:summary_date]) : Date.yesterday
  rescue ArgumentError
    nil
  end

  def check_authorization
    authorize(:'auditoria/daily_jobs')
  end
end

# Etapa 1 del pipeline diario de Auditor IA: recorre conversaciones con
# actividad reciente y encola el analisis existente (Auditoria::
# ConversationAnalyzerJob) para cada una -- el propio servicio se autosalta
# sin gastar si needs_analysis? es falso (ver conversation_analyzer_service.rb),
# asi que no hace falta filtrar con cuidado aqui, solo acotar el universo.
#
# Solo mensajes de los ultimos RECENT_ACTIVITY_WINDOW dias a proposito, no
# "nunca analizada" sin limite de tiempo -- una conversacion vieja sin
# actividad reciente no aporta nada al rollup de "ayer" (etapa 2) y barrer
# TODO el historial jamas analizado en la primera corrida podria agotar de
# un golpe el presupuesto mensual completo. Un backfill real de historia
# vieja, si alguna vez se necesita, deberia ser un rake task deliberado, no
# este job automatico.
class Auditoria::DailyConversationAnalysisSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  RECENT_ACTIVITY_WINDOW = 3.days

  # account_id es opcional (default: todas las cuentas, lo que usa el cron
  # real) para que un admin pueda disparar la corrida solo de SU cuenta
  # desde Settings sin afectar otras cuentas con el feature activo -- ver
  # Api::V1::Accounts::Auditoria::DailyJobsController.
  #
  # unbounded: true quita el limite de RECENT_ACTIVITY_WINDOW (usa
  # Auditoria::BacklogCandidateFinder en su lugar) -- SOLO para un catch-up
  # manual puntual de una cuenta especifica (ver #run_full_backlog en el
  # controller), nunca para el cron real. El guard de abajo evita que
  # unbounded combinado con "todas las cuentas" se cuele por error algun dia.
  #
  # track_progress: true por defecto (incluida la corrida real del cron) --
  # sin esto la corrida nocturna no deja rastro visible en ningun lado:
  # Auditoria::PipelineRunTracker nunca se escribe, y PipelineProgressCard.vue
  # (que hace poll de /progress al montar, sin depender de quien disparo la
  # corrida) siempre ve 'idle' aunque el cron ya haya procesado todo -- el
  # admin termina corriendolo el mismo cada manana creyendo que el cron no
  # funciona. El TTL de 6h del tracker alcanza para cubrir la ventana en que
  # un admin revisa la pantalla despues de la corrida nocturna.
  def perform(account_id: nil, unbounded: false, track_progress: true)
    return if unbounded && account_id.blank?

    kind = unbounded ? 'backlog' : 'conversation_analysis'
    accounts = account_id ? Account.where(id: account_id) : Account.all
    accounts.find_each { |account| enqueue_for_account(account, unbounded, kind, track_progress) }
  end

  # Clase, no instancia -- reusado por Auditoria::ManualRunEstimateService
  # para calcular el mismo universo de candidatos sin duplicar la logica de
  # la ventana de 3 dias.
  def self.candidate_conversation_ids(account, unbounded:)
    return Auditoria::BacklogCandidateFinder.conversation_ids(account) if unbounded

    account.conversations
           .joins(:messages)
           .where(messages: { message_type: [:incoming, :outgoing], created_at: RECENT_ACTIVITY_WINDOW.ago.. })
           .distinct
           .pluck(:id)
  end

  private

  def enqueue_for_account(account, unbounded, kind, track_progress)
    return unless account.feature_enabled?('auditoria')

    candidate_ids = self.class.candidate_conversation_ids(account, unbounded: unbounded)
    Auditoria::PipelineRunTracker.start!(account, kind, total: candidate_ids.size) if track_progress

    # Escalonado (perform_in con offset creciente) en vez de perform_later
    # puro -- el log de gasto se escribe DESPUES de la llamada a OpenAI, asi
    # que Sidekiq procesando muchas de golpe en paralelo podria dejar pasar
    # el chequeo de limite mensual a varias antes de que cualquiera
    # persista su log (TOCTOU). Un segundo de separacion es suficiente para
    # que casi siempre se procesen una a la vez sin montar un lock nuevo.
    candidate_ids.each_with_index do |conversation_id, index|
      Auditoria::ConversationAnalyzerJob.set(wait: index.seconds)
                                        .perform_later(conversation_id, triggered_by: :batch,
                                                                        pipeline_run_kind: track_progress ? kind : nil)
    end
  end
end

Auditoria::DailyConversationAnalysisSchedulerJob.prepend_mod_with('Auditoria::DailyConversationAnalysisSchedulerJob')

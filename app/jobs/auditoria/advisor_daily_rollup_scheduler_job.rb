# Etapa 2 del pipeline diario de Auditor IA (ver Auditoria::
# DailyConversationAnalysisSchedulerJob para la etapa 1, que debe correr
# horas antes -- las categorias AI dependen de que esa etapa ya corrio).
# Por cada asesor que atendio al menos una conversacion ese dia, encola
# Auditoria::AdvisorDailyRollupJob para sintetizar su dia.
#
# summary_date es parametro (default ayer, lo que usa el cron real) para que
# rake auditoria:run_daily_advisor_rollup pueda pedir una fecha especifica
# en una corrida manual -- ver lib/tasks/auditoria.rake. account_id es
# opcional por el mismo motivo que en DailyConversationAnalysisSchedulerJob
# -- ver Api::V1::Accounts::Auditoria::DailyJobsController.
class Auditoria::AdvisorDailyRollupSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  KIND = 'advisor_rollup'.freeze

  # track_progress: true por defecto (incluida la corrida real del cron) --
  # ver el mismo comentario en Auditoria::DailyConversationAnalysisSchedulerJob#perform.
  def perform(summary_date: Date.yesterday, account_id: nil, track_progress: true)
    accounts = account_id ? Account.where(id: account_id) : Account.all
    accounts.find_each do |account|
      next unless account.feature_enabled?('auditoria')

      agent_ids = self.class.agent_ids_with_activity(account, summary_date)
      Auditoria::PipelineRunTracker.start!(account, KIND, total: agent_ids.size) if track_progress

      agent_ids.each_with_index do |user_id, index|
        Auditoria::AdvisorDailyRollupJob.set(wait: index.seconds)
                                        .perform_later(account.id, user_id, summary_date, triggered_by: :batch,
                                                                                          pipeline_run_kind: track_progress ? KIND : nil)
      end
    end
  end

  # Clase, no instancia -- reusado por Auditoria::ManualRunEstimateService
  # para calcular el mismo universo de candidatos sin duplicar logica.
  def self.agent_ids_with_activity(account, summary_date)
    account.messages
           .where(created_at: summary_date.all_day)
           .where.not(conversation_id: excluded_conversation_ids(account))
           .pluck(Arel.sql("#{Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES}->>'auditoria_source_user_id'"))
           .compact
           .uniq
           .map(&:to_i)
  end

  def self.excluded_conversation_ids(account)
    account.conversations.tagged_with(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE).ids
  end
end

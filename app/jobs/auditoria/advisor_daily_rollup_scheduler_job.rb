# Etapa 2 del pipeline diario de Auditor IA (ver Auditoria::
# DailyConversationAnalysisSchedulerJob para la etapa 1, que debe correr
# horas antes -- las categorias AI dependen de que esa etapa ya corrio).
# Por cada asesor que atendio al menos una conversacion ese dia, encola
# Auditoria::AdvisorDailyRollupJob para sintetizar su dia.
#
# summary_date es parametro (default ayer, lo que usa el cron real) para que
# rake auditoria:run_daily_advisor_rollup pueda pedir una fecha especifica
# en una corrida manual -- ver lib/tasks/auditoria.rake.
class Auditoria::AdvisorDailyRollupSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(summary_date: Date.yesterday)
    Account.find_each do |account|
      next unless account.feature_enabled?('auditoria')

      agent_ids_with_activity(account, summary_date).each_with_index do |user_id, index|
        Auditoria::AdvisorDailyRollupJob.set(wait: index.seconds).perform_later(account.id, user_id, summary_date, triggered_by: :batch)
      end
    end
  end

  private

  def agent_ids_with_activity(account, summary_date)
    account.messages
           .where(created_at: summary_date.all_day)
           .where.not(conversation_id: excluded_conversation_ids(account))
           .pluck(Arel.sql("#{Auditoria::MessageAnnotatorService::UNWRAP_CONTENT_ATTRIBUTES}->>'auditoria_source_user_id'"))
           .compact
           .uniq
           .map(&:to_i)
  end

  def excluded_conversation_ids(account)
    account.conversations.tagged_with(Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE).ids
  end
end

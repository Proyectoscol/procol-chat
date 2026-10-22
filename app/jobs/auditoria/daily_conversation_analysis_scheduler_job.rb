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

  def perform
    Account.find_each do |account|
      next unless account.feature_enabled?('auditoria')

      # Escalonado (perform_in con offset creciente) en vez de perform_later
      # puro -- el log de gasto se escribe DESPUES de la llamada a OpenAI, asi
      # que Sidekiq procesando muchas de golpe en paralelo podria dejar pasar
      # el chequeo de limite mensual a varias antes de que cualquiera
      # persista su log (TOCTOU). Un segundo de separacion es suficiente para
      # que casi siempre se procesen una a la vez sin montar un lock nuevo.
      candidate_conversation_ids(account).each_with_index do |conversation_id, index|
        Auditoria::ConversationAnalyzerJob.perform_in(index.seconds, conversation_id, triggered_by: :batch)
      end
    end
  end

  private

  def candidate_conversation_ids(account)
    account.conversations
           .joins(:messages)
           .where(messages: { message_type: [:incoming, :outgoing], created_at: RECENT_ACTIVITY_WINDOW.ago.. })
           .distinct
           .pluck(:id)
  end
end

Auditoria::DailyConversationAnalysisSchedulerJob.prepend_mod_with('Auditoria::DailyConversationAnalysisSchedulerJob')

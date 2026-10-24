# Lee los resumenes diarios ya sintetizados por Auditoria::
# AdvisorDailyRollupJob (ver config/schedule.yml) -- no corre IA en el
# request, solo lee lo que el job nocturno ya persistio en
# Auditoria::AdvisorDailySummary.
class V2::Reports::AuditoriaAdvisorDailyRollupBuilder
  pattr_initialize [:account!, :params!]

  def build
    { summaries: summaries.map { |summary| serialize(summary) } }
  end

  private

  def summaries
    scope = account.auditoria_advisor_daily_summaries.where(summary_date: range)
    scope = scope.where(user_id: user_ids) if user_ids.present?
    scope.order(summary_date: :desc)
  end

  def serialize(summary)
    {
      user_id: summary.user_id,
      summary_date: summary.summary_date.iso8601,
      conversations_count: summary.conversations_count,
      category_counts: summary.category_counts,
      feedback_tags_positive: summary.feedback_tags_positive,
      feedback_tags_negative: summary.feedback_tags_negative,
      feedback_tags_negative_detail: summary.feedback_tags_negative_detail,
      results: summary.results,
      generated_at: summary.generated_at
    }
  end

  def range
    Time.zone.at(params[:since].to_i).to_date..Time.zone.at(params[:until].to_i).to_date
  end

  # Para un admin restringido (el controller ya fuerza inbox_id a su scope
  # antes de llegar aqui), acota a agentes miembros de esos inbox(es) en vez
  # de intentar re-filtrar por conversacion el agregado ya calculado -- el
  # resumen se genera una vez por agente/dia a nivel de cuenta completa (ver
  # Auditoria::AdvisorDailyRollupService), no por inbox.
  def user_ids
    @user_ids ||= [requested_user_ids, inbox_scoped_user_ids].compact.reduce(:&)
  end

  def requested_user_ids
    Array(params[:user_id]).map(&:to_i).presence
  end

  def inbox_scoped_user_ids
    return nil if inbox_ids.blank?

    InboxMember.where(inbox_id: inbox_ids).distinct.pluck(:user_id)
  end

  def inbox_ids
    Array(params[:inbox_id]).map(&:to_i).presence
  end
end

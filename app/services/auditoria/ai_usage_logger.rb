# Punto unico de registro y control de gasto de IA para Auditoria - lo usan
# tanto Auditoria::ConversationAnalyzerService (analisis de conversacion)
# como Auditoria::AudioTranscriptionService (transcripcion de audio), para
# que ambos queden en el mismo log y respeten el mismo tope mensual.
class Auditoria::AiUsageLogger
  def self.within_limit?(account)
    cost_limit = account.auditoria_ai_monthly_cost_limit_usd.presence&.to_f
    token_limit = account.auditoria_ai_monthly_token_limit.presence&.to_i
    return true if cost_limit.blank? && token_limit.blank?

    totals = current_month_totals(account)
    within_cost_limit?(totals, cost_limit) && within_token_limit?(totals, token_limit)
  end

  def self.within_cost_limit?(totals, cost_limit)
    cost_limit.blank? || totals[:cost_usd].to_f < cost_limit
  end
  private_class_method :within_cost_limit?

  def self.within_token_limit?(totals, token_limit)
    token_limit.blank? || totals[:total_tokens].to_i < token_limit
  end
  private_class_method :within_token_limit?

  def self.current_month_totals(account)
    scope = account.auditoria_ai_usage_logs.where(created_at: Time.current.beginning_of_month..)
    {
      cost_usd: scope.sum(:cost_usd),
      total_tokens: scope.sum(:total_tokens)
    }
  end

  def self.log!(attrs)
    usage = attrs.fetch(:usage)
    Auditoria::AiUsageLog.create!(
      account: attrs.fetch(:account),
      conversation: attrs[:conversation],
      message: attrs[:message],
      feature: attrs.fetch(:feature),
      model: attrs.fetch(:model),
      prompt_tokens: usage['prompt_tokens'],
      completion_tokens: usage['completion_tokens'],
      total_tokens: usage['total_tokens'],
      cost_usd: attrs[:cost_usd],
      triggered_by: attrs.fetch(:triggered_by)
    )
  end
end

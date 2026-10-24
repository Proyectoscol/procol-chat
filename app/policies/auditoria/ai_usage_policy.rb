class Auditoria::AiUsagePolicy < ApplicationPolicy
  def summary?
    @account_user.administrator? || @account_user.agent?
  end

  def index?
    @account_user.administrator? || @account_user.agent?
  end

  # Alcance global de cuenta (limite de gasto, modelo de IA) -- igual que
  # Auditoria::DailyJobsPolicy, reservado al administrator SIN restriccion.
  def update_settings?
    @account_user.administrator? && !@account_user.inbox_restricted?
  end
end

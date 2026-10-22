# Disparar el pipeline diario a mano gasta IA de TODA la cuenta (no se puede
# acotar por inbox, a diferencia del resto de reportes/listados) -- reservado
# al administrator SIN restriccion, igual que las demas acciones de alcance
# global ya reservadas esta semana (ver AccountUser#inbox_restricted?).
class Auditoria::DailyJobsPolicy < ApplicationPolicy
  def run_conversation_analysis?
    unrestricted_administrator?
  end

  def run_advisor_rollup?
    unrestricted_administrator?
  end

  def backlog_estimate?
    unrestricted_administrator?
  end

  def run_full_backlog?
    unrestricted_administrator?
  end

  private

  def unrestricted_administrator?
    @account_user.administrator? && !@account_user.inbox_restricted?
  end
end

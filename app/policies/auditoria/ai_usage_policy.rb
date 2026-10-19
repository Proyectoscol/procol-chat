class Auditoria::AiUsagePolicy < ApplicationPolicy
  def summary?
    @account_user.administrator? || @account_user.agent?
  end

  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update_settings?
    @account_user.administrator?
  end
end

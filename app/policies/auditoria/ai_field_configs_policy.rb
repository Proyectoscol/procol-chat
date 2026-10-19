class Auditoria::AiFieldConfigsPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator?
  end
end

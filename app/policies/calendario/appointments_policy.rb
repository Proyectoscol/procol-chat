class Calendario::AppointmentsPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    index?
  end

  def update?
    index?
  end

  def agenda?
    index?
  end

  def next_agenda_date?
    index?
  end
end

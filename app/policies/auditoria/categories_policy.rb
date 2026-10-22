class Auditoria::CategoriesPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    unrestricted_administrator?
  end

  def update?
    unrestricted_administrator?
  end

  def destroy?
    unrestricted_administrator?
  end

  private

  # Gestionar categorias (crear/editar/borrar) es una accion de configuracion
  # de cuenta, no de inbox -- reservada al administrador SIN restriccion,
  # igual que Auditoria::DailyJobsPolicy. Un admin restringido solo VE la
  # lista ya filtrada por CategoriesController#index.
  def unrestricted_administrator?
    @account_user.administrator? && !@account_user.inbox_restricted?
  end
end

# Procol Auditoria viene de reemplazar la imagen de un deploy que ya tenia
# ~40 agentes y ~660 conversaciones creados a mano, cada uno con su propia
# verificacion manual (UPDATE confirmed_at) y su propia regla de asignacion
# "Source: <nombre>" armada a mano en el dashboard. Para que ese swap de
# imagen no requiera repetir ese trabajo manual ni arriesgue tocar una cuenta
# equivocada, esta migracion:
#   1. prende el feature "auditoria" para la cuenta indicada en
#      AUDITORIA_ACCOUNT_ID (ver .env.example) - sin esa env var, no hace nada;
#   2. corre Auditoria::AgentReconcilerService, que es idempotente: no
#      re-verifica a quien ya esta confirmado ni duplica una regla que ya
#      exista, asi que es seguro que esto corra contra datos que ya estaban
#      bien armados a mano.
class EnableAuditoriaForAccountAndReconcileAgents < ActiveRecord::Migration[7.1]
  def up
    account_id = ENV['AUDITORIA_ACCOUNT_ID'].presence

    if account_id.blank?
      say 'AUDITORIA_ACCOUNT_ID no esta configurado - omitiendo activacion de Auditoria.'
      return
    end

    account = Account.find(account_id)
    account.enable_features!('auditoria')

    result = Auditoria::AgentReconcilerService.new(account: account).call
    say "Auditoria (account_id=#{account.id}): verificados #{result[:confirmed].inspect}"
    say "Auditoria (account_id=#{account.id}): reglas creadas #{result[:rules_created].inspect}"
    return if result[:orphan_rules].blank?

    say "Auditoria (account_id=#{account.id}): ATENCION - reglas sin agente que coincida #{result[:orphan_rules].inspect}"
  end
end

# El item "Agente IA" del sidebar (bajo Campanas) enlaza a la pagina de
# Captain, cuya visibilidad depende del feature flag "captain_integration"
# (ver captain.routes.js meta.featureFlag + Policy/SidebarGroupLeaf). Ese
# flag viene `enabled: false, premium: true` en config/features.yml, asi que
# ninguna cuenta lo trae activo por defecto - de ahi que el item sea
# invisible en un deploy nuevo aunque el codigo del enlace ya exista.
#
# Mismo patron que 20260120121402_enable_captain_tasks_for_existing_accounts.rb:
# una migracion de datos, no solo un cambio de default, porque
# ACCOUNT_LEVEL_FEATURE_DEFAULTS (Featurable#enable_default_features) solo
# corre en cuentas NUEVAS (before_create) - las cuentas que ya existen en
# produccion necesitan que se las active explicitamente aqui para que el
# proximo deploy ya las traiga encendidas sin un paso manual en Super Admin.
#
# Se limita a cuentas con "cartera" ya activo: el Agente IA en este fork es
# parte del paquete de Campanas, no una feature general de soporte - no
# tiene sentido prenderla en una cuenta que no usa cartera.
class EnableCaptainIntegrationForCarteraAccounts < ActiveRecord::Migration[7.1]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each do |account|
        account.enable_features!('captain_integration') if account.feature_enabled?('cartera')
      end
    end
  end
end

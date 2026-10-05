# "Sacar de la campana por 30 dias": un humano ya gestiono el caso por fuera
# (acuerdo de pago, etc.) y no debe recibir mas comunicaciones hasta esta
# fecha. Va en columnas propias y no en no_cobrar/razon_no_cobrar porque
# PriorizacionService#guardar_caso recalcula esos dos en cada corrida -
# estas tres sobreviven el recalculo porque el servicio no las toca.
class AddExclusionToCarteraCasos < ActiveRecord::Migration[7.1]
  def change
    add_column :cartera_casos, :excluido_hasta, :datetime
    add_column :cartera_casos, :excluido_motivo, :string
    add_reference :cartera_casos, :excluido_por_user, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end

class AddTramoToCarteraCasos < ActiveRecord::Migration[7.1]
  def change
    add_column :cartera_casos, :tramo, :string
    add_column :cartera_casos, :dias_vencido_max, :integer
    add_index :cartera_casos, :tramo
  end
end

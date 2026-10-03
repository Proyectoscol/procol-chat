class CreateCarteraClientes < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_clientes do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.string :external_id, null: false
      t.integer :tipo_deudor, null: false
      t.string :identificacion, null: false
      t.string :nombre, null: false
      t.string :email
      t.string :telefono
      t.string :sucursal
      t.decimal :cupo_asignado, precision: 18, scale: 2
      t.boolean :es_estrategico, null: false, default: false
      t.integer :grupo_control

      t.timestamps
    end

    add_index :cartera_clientes, [:account_id, :external_id], unique: true
  end
end

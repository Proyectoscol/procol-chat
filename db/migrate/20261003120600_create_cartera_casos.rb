class CreateCarteraCasos < ActiveRecord::Migration[7.1]
  def change
    create_table :cartera_casos do |table|
      add_caso_columns(table)
      table.timestamps
    end

    add_caso_indexes
  end

  def add_caso_columns(table)
    table.references :account, null: false, foreign_key: { on_delete: :cascade }
    table.references :cliente, null: false, foreign_key: { to_table: :cartera_clientes, on_delete: :cascade }
    table.string :estado, null: false, default: 'abierto'
    table.decimal :prioridad_score, precision: 10, scale: 4
    table.jsonb :factores_score
    table.string :nivel_escalamiento, null: false, default: 'persuasivo'
    table.boolean :no_cobrar, null: false, default: false
    table.string :razon_no_cobrar
    table.boolean :revisado, null: false, default: false
    table.boolean :descartado, null: false, default: false
    table.decimal :saldo_abierto, precision: 18, scale: 2
    table.integer :puntaje_riesgo
    table.integer :score_credito
    table.decimal :total_facturado_historico, precision: 18, scale: 2
    table.integer :facturas_abiertas_cantidad
    table.datetime :fecha_primera_factura
  end

  def add_caso_indexes
    add_index :cartera_casos, [:account_id, :cliente_id], unique: true
    add_index :cartera_casos, :prioridad_score
    add_index :cartera_casos, :saldo_abierto
    add_index :cartera_casos, :puntaje_riesgo
  end
end

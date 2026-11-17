class CreateCalendarioServicePrices < ActiveRecord::Migration[7.1]
  def change
    create_table :calendario_service_prices do |t|
      t.references :service, null: false, foreign_key: { to_table: :calendario_services, on_delete: :cascade }
      t.references :payer, foreign_key: { to_table: :calendario_payers, on_delete: :cascade }
      t.integer :price, null: false
      t.integer :copago

      t.timestamps
    end

    add_index :calendario_service_prices, [:service_id, :payer_id], unique: true,
                                                                      name: 'index_calendario_service_prices_on_service_and_payer'
    # payer_id nulo = precio por defecto (particular) -- Postgres no deduplica NULLs en el
    # indice compuesto de arriba, asi que el "solo un default por servicio" necesita este
    # indice parcial aparte.
    add_index :calendario_service_prices, :service_id, unique: true, where: 'payer_id IS NULL',
                                                         name: 'index_calendario_service_prices_on_service_default'
  end
end

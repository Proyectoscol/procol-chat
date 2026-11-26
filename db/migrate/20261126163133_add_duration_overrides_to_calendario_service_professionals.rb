class AddDurationOverridesToCalendarioServiceProfessionals < ActiveRecord::Migration[7.1]
  def change
    add_column :calendario_service_professionals, :eps_duration_minutes, :integer
    add_column :calendario_service_professionals, :private_duration_minutes, :integer
  end
end

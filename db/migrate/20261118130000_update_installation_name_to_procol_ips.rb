class UpdateInstallationNameToProcolIps < ActiveRecord::Migration[7.1]
  def up
    %w[INSTALLATION_NAME BRAND_NAME].each do |key|
      config = InstallationConfig.find_by(name: key)
      next unless config
      next if config.value == 'Procol IPS'

      config.update!(value: 'Procol IPS')
    end
  end

  def down
    %w[INSTALLATION_NAME BRAND_NAME].each do |key|
      config = InstallationConfig.find_by(name: key)
      next unless config

      config.update!(value: 'Chatwoot')
    end
  end
end

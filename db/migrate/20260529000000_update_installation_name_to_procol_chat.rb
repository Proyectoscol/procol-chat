class UpdateInstallationNameToProcolChat < ActiveRecord::Migration[7.0]
  def up
    %w[INSTALLATION_NAME BRAND_NAME].each do |key|
      config = InstallationConfig.find_by(name: key)
      next unless config
      next if config.value == 'Procol-Chat'

      config.update!(value: 'Procol-Chat')
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

# Canal de Voz (Asterisk) del fork. Sigue el patrón de Channel::TwilioSms /
# Channel::Whatsapp (include Channelable + table propia + provider_config jsonb).
# Overlay enterprise, aislado del rebase sobre upstream.
# == Schema Information
#
# Table name: channel_voice
#
#  id              :bigint           not null, primary key
#  phone_number    :string           not null
#  provider_config :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_channel_voice_on_account_id                   (account_id)
#  index_channel_voice_on_account_id_and_phone_number  (account_id,phone_number) UNIQUE
#
class Channel::Voice < ApplicationRecord
  include Channelable

  self.table_name = 'channel_voice'

  # provider_config se edita como hash completo (igual que Channel::Whatsapp): las
  # claves anidadas dinámicas (ivr_digit_to_team) no sobreviven a strong-params
  # enumerados, así que se permite el hash abierto.
  EDITABLE_ATTRS = [:phone_number, { provider_config: {} }].freeze

  # Defaults de la config tunable por cliente sin deploy (DEX-3). Claves string para
  # mergear limpio con el jsonb; se aplican en before_validation sin pisar lo guardado.
  PROVIDER_CONFIG_DEFAULTS = {
    'wss_host' => nil,
    'wss_port' => '8089',
    'ivr_digit_to_team' => {},
    'shared_numbers' => [],
    'max_queue_size' => 10,
    'work_saturday' => false,
    'absence_threshold_days' => 2,
    'enable_callback' => true,
    'staging' => false
  }.freeze

  validates :phone_number, presence: true, uniqueness: { scope: :account_id }

  before_validation :apply_provider_config_defaults

  def name
    'Voice'
  end

  def voice_enabled?
    true
  end

  private

  def apply_provider_config_defaults
    self.provider_config = PROVIDER_CONFIG_DEFAULTS.merge(provider_config || {})
  end
end

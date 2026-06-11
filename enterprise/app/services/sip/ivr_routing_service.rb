# Resuelve el Team destino a partir del dígito que el cliente marcó en el IVR.
# El mapeo dígito→Team vive en la config del Channel::Voice bajo `ivr_digit_to_team`
# (p. ej. { "1" => team_pereira_id, "2" => team_medellin_id, "3" => team_manizales_id }),
# editable por el admin sin migración (§2/§3 del plan).
#
# Devuelve el Team (scopeado a la cuenta) o nil si el dígito es inválido, no está
# mapeado, la config no existe o el Team fue borrado. Nunca explota: alimenta
# ctx.team, que luego TeamRoundRobinRule usa para el round-robin del Team.
class Sip::IvrRoutingService
  CONFIG_KEY = 'ivr_digit_to_team'

  attr_reader :inbox, :digit

  def self.call(inbox:, digit:)
    new(inbox: inbox, digit: digit).call
  end

  def initialize(inbox:, digit:)
    @inbox = inbox
    @digit = digit
  end

  # @return [Team, nil]
  def call
    team_id = mapping[digit.to_s]
    return nil if team_id.blank?

    inbox.account.teams.find_by(id: team_id)
  end

  private

  # { "1" => team_id, ... } desde la config del canal de Voz. {} si no hay canal/config.
  def mapping
    channel = inbox&.channel
    return {} unless channel.respond_to?(:provider_config)

    config = channel.provider_config || {}
    config.with_indifferent_access[CONFIG_KEY] || {}
  end
end

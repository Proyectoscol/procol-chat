# Verifica agentes sin confirmar y crea la regla de asignacion "Source: <nombre>"
# que falte, para cada agente de una cuenta con el feature "auditoria" activo.
# Idempotente: no re-verifica a quien ya esta confirmado ni duplica una regla
# que ya exista, asi que es seguro re-ejecutarlo (deploy inicial contra una
# cuenta ya poblada, o despues de agregar agentes nuevos en bloque).
#
# create_assignment_rule! tambien la usa AccountUser#create_auditoria_assignment_rule
# para el caso de un solo agente nuevo, asi el shape de la regla vive en un solo lugar.
class Auditoria::AgentReconcilerService
  pattr_initialize [:account!]

  SOURCE_PREFIX = 'Source: '.freeze

  def self.source_tag_for(user)
    "#{SOURCE_PREFIX}#{user.name}"
  end

  def self.create_assignment_rule!(account:, user:)
    source_tag = source_tag_for(user)
    account.automation_rules.create!(
      name: user.name,
      description: source_tag,
      event_name: 'message_created',
      conditions: [{
        'values' => [source_tag],
        'attribute_key' => 'content',
        'filter_operator' => 'contains',
        'custom_attribute_type' => ''
      }],
      actions: [{ 'action_name' => 'assign_agent', 'action_params' => [user.id] }]
    )
  end

  def call
    confirmed = []
    rules_created = []

    agents.each do |user|
      confirmed << user.name if confirm_agent(user)
      rules_created << user.name if create_missing_rule(user)
    end

    { confirmed: confirmed, rules_created: rules_created, orphan_rules: orphan_rules }
  end

  private

  def agents
    @agents ||= account.account_users.includes(:user).map(&:user)
  end

  def confirm_agent(user)
    return false if user.confirmed?

    user.confirm
  end

  # Compara ignorando tildes/mayusculas/espacios (normalize_name) -- si ya
  # existe una regla para este agente con distinta tilde/mayuscula (por
  # ejemplo, una armada a mano antes de que existiera este reconciliador),
  # no crea una duplicada.
  def create_missing_rule(user)
    normalized_tag = Auditoria::MessageAnnotatorService.normalize_name(self.class.source_tag_for(user))
    return false if assignment_rules.any? { |rule| Auditoria::MessageAnnotatorService.normalize_name(rule.description) == normalized_tag }

    assignment_rules << self.class.create_assignment_rule!(account: account, user: user)
    true
  end

  # Reglas de asignacion por agente cuyo "Source: <nombre>" ya no coincide con
  # ningun agente actual - sintoma de un nombre con error de tipeo o un agente
  # renombrado despues de crear la regla. Normalizado para no marcar como
  # huerfana una regla que solo difiere en tilde/mayuscula/espacio.
  def orphan_rules
    agent_names_normalized = agents.map { |u| Auditoria::MessageAnnotatorService.normalize_name(u.name) }
    rules = assignment_rules.reject do |rule|
      agent_names_normalized.include?(Auditoria::MessageAnnotatorService.normalize_name(rule.description.delete_prefix(SOURCE_PREFIX)))
    end
    rules.map { |rule| { id: rule.id, description: rule.description } }
  end

  def assignment_rules
    @assignment_rules ||= account.automation_rules.where(event_name: 'message_created')
                                 .to_a.select { |rule| rule.description.to_s.start_with?(SOURCE_PREFIX) }
  end
end

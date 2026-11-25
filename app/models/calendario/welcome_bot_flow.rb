# Configuracion de un bot de triage: a que texto reacciona (match_type +
# match_value) y que secuencia de preguntas hace. Varios pueden coexistir en
# la misma bandeja -- pedido explicito del usuario: "mas adelante dependiendo
# de lo que la persona escriba quiero enviarle otro bot de triaje [...]
# deben haber la posibilidad de configurarse varios".
#
# steps (jsonb), cada paso:
#   { "type" => "ask", "ask" => "...", "options" => ["...", "..."], "if" => { "step" => 0, "equals" => "..." } }
# "type" es opcional, default "ask" (pregunta + opciones de texto, el
# comportamiento historico, sin cambios). "if" tambien es opcional -- sin
# el, el paso siempre aplica; con el, solo si la respuesta de un paso
# anterior fue exactamente ese valor (ver
# Calendario::WelcomeBotFlowRunner#applicable_step?).
#
# Tipos de paso adicionales (todos resueltos en WelcomeBotFlowRunner), para
# el flujo de "cita existente" -- ninguno espera mas que el "if" para saber
# cuando aplica, y los que no son preguntas se ejecutan y avanzan solos:
#   "lookup_appointment" (espera respuesta): busca la proxima cita futura
#     del contacto (nunca de otro contacto -- siempre via
#     conversation.contact.calendario_appointments.upcoming) y la confirma
#     con "ask_template" (texto con variables Liquid: appointment.date,
#     appointment.time, appointment.service_name,
#     appointment.professional_name), con "options" (default: Reagendar /
#     Cancelar / Hablar con recepcion). Si no hay cita futura, manda
#     "empty_message" y transfiere directo a recepcion.
#   "perform_cancellation" (accion): lee la respuesta del paso anterior
#     (lista de espera vs definitiva, por "waitlist_keyword"/
#     "definitive_keyword") y cancela la cita encontrada en el paso
#     "lookup_appointment" previo.
#   "request_reschedule" (accion): pone la cita en pending y manda
#     "ack_message" al paciente.
#   "handoff" (accion): transfiere a recepcion de inmediato con
#     "ack_message".
#   "notify" (accion, generico): manda "ack_message"/"ack_message_key" (sin
#     botones) y avanza solo al proximo paso aplicable -- no toca ninguna
#     cita. Pensado para mensajes "de paso" que no esperan respuesta (ej. el
#     aviso de que ginecologia no atiende pacientes en embarazo, insertado
#     como un paso "ask" de Si/No seguido de este tipo cuando la respuesta
#     es "Si").
# == Schema Information
#
# Table name: calendario_welcome_bot_flows
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  escalation_message :text
#  match_type         :string           default("default"), not null
#  match_value        :string
#  name               :string           not null
#  priority           :integer          default(0), not null
#  reminder_schedule  :jsonb            not null
#  steps              :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  inbox_id           :bigint           not null
#
# Indexes
#
#  index_calendario_welcome_bot_flows_on_account_id  (account_id)
#  index_calendario_welcome_bot_flows_on_inbox_id    (inbox_id)
#  index_one_active_default_flow_per_inbox           (inbox_id,match_type) UNIQUE WHERE (((match_type)::text = 'default'::text) AND (active = true))
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#
class Calendario::WelcomeBotFlow < ApplicationRecord
  self.table_name = 'calendario_welcome_bot_flows'

  MATCH_TYPES = %w[default keyword].freeze

  belongs_to :account
  belongs_to :inbox
  has_many :bot_sessions, class_name: 'Calendario::BotSession', dependent: :destroy

  validates :name, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES }
  validates :match_value, presence: true, if: :keyword?
  validates :match_value, absence: true, unless: :keyword?
  validate :inbox_belongs_to_account

  scope :active, -> { where(active: true) }

  def keyword?
    match_type == 'keyword'
  end

  def default?
    match_type == 'default'
  end

  # Normaliza igual que Calendario::NoShowReplyListener -- minusculas, sin
  # tildes -- para que "Particular"/"PARTICULAR"/"particular" matcheen igual.
  def self.normalize(text)
    text.to_s.downcase.unicode_normalize(:nfkd).gsub(/[^\x00-\x7F]/, '').strip
  end

  def matches?(text)
    return false unless keyword?

    self.class.normalize(text).include?(self.class.normalize(match_value))
  end

  # El primer keyword que matchea por prioridad (mas alto primero), o el
  # default de la bandeja si ninguno matchea.
  def self.match_for(inbox, text)
    flows = where(inbox: inbox).active.order(priority: :desc)
    flows.find { |flow| flow.keyword? && flow.matches?(text) } ||
      flows.find(&:default?)
  end

  # Advertencias (NO bloquean guardar -- ver nota abajo) sobre pasos con
  # opciones que no mandan un quick-reply real de WhatsApp. Pedido explicito
  # del usuario (rediseño 2026-11-25): "todas deben tener plantilla de
  # WhatsApp aprobada". No se implementa como validacion dura porque el
  # flow real de produccion YA tiene 2 pasos asi (lista de espera, cita
  # existente) y bloquear el guardado los dejaria sin poder editarse hasta
  # crear esas plantillas -- mismo criterio no-bloqueante que ya usa
  # AppointmentEventTriggerFormModal (fuerza test_mode, no impide guardar).
  # El frontend (WelcomeBotFlowFormModal.vue) muestra esto como aviso.
  STEP_TYPES_REQUIRING_OPTIONS_TEMPLATE = %w[ask lookup_appointment].freeze

  def missing_template_warnings
    approved_content_sids = approved_twilio_content_sids
    Array(steps).each_with_index.filter_map do |step, index|
      step_template_warning(step, index, approved_content_sids)
    end
  end

  private

  def inbox_belongs_to_account
    return if inbox.blank? || inbox.account_id == account_id

    errors.add(:inbox, :invalid)
  end

  def step_needs_template_check?(step)
    STEP_TYPES_REQUIRING_OPTIONS_TEMPLATE.include?(step['type'] || 'ask') &&
      Array(step['options'] || step['buttons']).present?
  end

  def step_template_warning(step, index, approved_content_sids)
    return unless step_needs_template_check?(step)

    content_sid = step['content_sid']
    return "Paso #{index + 1}: tiene opciones pero no tiene plantilla de WhatsApp asignada" if content_sid.blank?
    return if approved_content_sids.blank? || approved_content_sids.include?(content_sid)

    "Paso #{index + 1}: la plantilla asignada no está aprobada"
  end

  # nil (no se pudo verificar, ej. canal no-Twilio) en vez de [] -- asi
  # missing_template_warnings no reporta de mas por falta de catalogo, solo
  # cuando SI hay catalogo y el content_sid elegido claramente no esta en
  # el de aprobados.
  def approved_twilio_content_sids
    templates = inbox&.channel&.try(:content_templates)
    return nil if templates.blank?

    Array(templates['templates']).select { |t| t['status'] == 'approved' }.pluck('content_sid')
  end
end

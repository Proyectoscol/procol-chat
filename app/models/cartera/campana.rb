# Una campana de cobro: cadencia, canales e IA que gobiernan como se
# contacta a los clientes en cartera_casos. Solo una campana puede estar
# "activa" por cuenta a la vez (indice unico parcial en la migracion) -
# las demas se pausan o archivan, nunca se borran.
# == Schema Information
#
# Table name: cartera_campanas
#
#  id                                  :bigint           not null, primary key
#  autorizacion_confirmada_at          :datetime
#  autorizacion_detalle                :text
#  autorizacion_fuente                 :string
#  dias_envio                          :integer          default([]), not null, is an Array
#  estado                              :string           default("borrador"), not null
#  hora_fin                            :time             not null
#  hora_inicio                         :time             not null
#  nombre                              :string           not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  account_id                          :bigint           not null
#  autorizacion_confirmada_por_user_id :bigint
#  captain_assistant_id                :bigint
#  inbox_email_id                      :bigint
#  inbox_whatsapp_id                   :bigint
#
# Indexes
#
#  idx_cartera_campanas_una_activa_por_cuenta      (account_id) UNIQUE WHERE ((estado)::text = 'activa'::text)
#  index_cartera_campanas_on_account_id            (account_id)
#  index_cartera_campanas_on_captain_assistant_id  (captain_assistant_id)
#  index_cartera_campanas_on_inbox_email_id        (inbox_email_id)
#  index_cartera_campanas_on_inbox_whatsapp_id     (inbox_whatsapp_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (captain_assistant_id => captain_assistants.id) ON DELETE => nullify
#  fk_rails_...  (inbox_email_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (inbox_whatsapp_id => inboxes.id) ON DELETE => nullify
#
class Cartera::Campana < ApplicationRecord
  self.table_name = 'cartera_campanas'

  ESTADOS = %w[borrador activa pausada archivada].freeze
  FUENTES_AUTORIZACION = %w[politica_privacidad terminos_condiciones contrato otro].freeze

  belongs_to :account
  belongs_to :inbox_whatsapp, class_name: 'Inbox', optional: true
  belongs_to :inbox_email, class_name: 'Inbox', optional: true
  belongs_to :captain_assistant, class_name: 'Captain::Assistant', optional: true
  belongs_to :autorizacion_confirmada_por, class_name: 'User', foreign_key: :autorizacion_confirmada_por_user_id, optional: true, inverse_of: false

  has_many :reglas, -> { order(:orden) }, class_name: 'Cartera::CampanaRegla', dependent: :destroy, inverse_of: :campana
  has_many :envios, class_name: 'Cartera::Envio', dependent: :destroy, inverse_of: :campana

  validates :nombre, :estado, :hora_inicio, :hora_fin, presence: true
  validates :estado, inclusion: { in: ESTADOS }
  validates :autorizacion_fuente, inclusion: { in: FUENTES_AUTORIZACION }, allow_nil: true
  validate :dias_envio_validos
  validate :horario_valido
  validate :horario_dentro_de_ley
  validate :autorizacion_completa_si_activa
  validate :una_sola_campana_activa, if: -> { estado == 'activa' }

  private

  def dias_envio_validos
    return if Array(dias_envio).all? { |dia| Cartera::Campanas::LeyCobranza.dia_permitido?(dia) }

    errors.add(:dias_envio, 'solo puede incluir lunes a sabado (Ley 2300 de 2023, art. 3 prohibe domingo)')
  end

  # Comparar columnas :time directamente con > no es confiable: Rails les
  # asigna una fecha ficticia (2000-01-01) que puede terminar distinta entre
  # dos atributos segun el path de lectura/escritura, igual que
  # AgentAvailabilitySchedule#in_window? - seconds_since_midnight evita eso.
  def horario_valido
    return if hora_inicio.blank? || hora_fin.blank?
    return if hora_fin.seconds_since_midnight > hora_inicio.seconds_since_midnight

    errors.add(:hora_fin, 'debe ser posterior a hora_inicio')
  end

  # Lun-vie 7-19, sabado 8-15 (Ley 2300 de 2023, art. 3). dias_envio_validos
  # ya rechazo domingo/valores fuera de rango, asi que solo faltan las horas.
  def horario_dentro_de_ley
    return if hora_inicio.blank? || hora_fin.blank?

    Array(dias_envio).each { |dia| validar_ventana_del_dia(dia) }
  end

  def validar_ventana_del_dia(dia)
    ventana = Cartera::Campanas::LeyCobranza.ventana_segundos(dia)
    return if ventana.nil? # dia invalido, ya reportado por dias_envio_validos

    nombre_dia = I18n.t('date.day_names')[dia]
    if hora_inicio.seconds_since_midnight < ventana.first
      errors.add(:hora_inicio, "para el dia #{nombre_dia} debe ser desde las #{ventana.first / 3600}:00 (Ley 2300 de 2023, art. 3)")
    end
    return unless hora_fin.seconds_since_midnight > ventana.last

    errors.add(:hora_fin, "para el dia #{nombre_dia} debe ser hasta las #{ventana.last / 3600}:00 (Ley 2300 de 2023, art. 3)")
  end

  # No se puede activar una campana sin declarar donde consta la
  # autorizacion del canal (Ley 2300 de 2023, art. 2) - cartera_clientes no
  # tiene ese dato por cliente, asi que esta declaracion a nivel de campana
  # es el unico control posible hoy.
  def autorizacion_completa_si_activa
    return unless estado == 'activa'
    return if autorizacion_fuente.present? && autorizacion_confirmada_por_user_id.present? && autorizacion_confirmada_at.present?

    errors.add(:base, 'Debe declarar la autorizacion del canal antes de activar la campana.')
  end

  def una_sola_campana_activa
    return if account.blank?

    otras_activas = account.cartera_campanas.where(estado: 'activa').where.not(id: id)
    errors.add(:estado, 'Ya hay otra campana activa en esta cuenta. Pausala o archivala primero.') if otras_activas.exists?
  end
end

# Una campana de cobro: cadencia, canales e IA que gobiernan como se
# contacta a los clientes en cartera_casos. Solo una campana puede estar
# "activa" por cuenta a la vez (indice unico parcial en la migracion) -
# las demas se pausan o archivan, nunca se borran.
# == Schema Information
#
# Table name: cartera_campanas
#
#  id                                  :bigint           not null, primary key
#  activada_en                         :datetime
#  autorizacion_confirmada_at          :datetime
#  autorizacion_detalle                :text
#  autorizacion_fuente                 :string
#  dias_envio                          :integer          default([]), not null, is an Array
#  estado                              :string           default("borrador"), not null
#  horas_envio                         :jsonb            not null
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

  validates :nombre, :estado, presence: true
  validates :estado, inclusion: { in: ESTADOS }
  validates :autorizacion_fuente, inclusion: { in: FUENTES_AUTORIZACION }, allow_nil: true
  validate :dias_envio_validos
  validate :horas_envio_validas
  validate :autorizacion_completa_si_activa
  validate :una_sola_campana_activa, if: -> { estado == 'activa' }

  before_save :marcar_primera_activacion

  # Hora exacta de envio para un dia de la semana (Date#wday, 0=domingo),
  # o nil si ese dia no tiene una hora configurada - usado por
  # Cartera::Campanas::CorridaService para decidir si "ahora" es el
  # momento de procesar casos. Mismo "dia ficticio" 2000-01-01 que usaban
  # hora_inicio/hora_fin, para poder comparar con .seconds_since_midnight.
  def hora_envio_para(wday)
    valor = horas_envio[wday.to_s]
    return nil if valor.blank?

    Time.zone.parse(valor)
  rescue ArgumentError
    nil
  end

  private

  # Solo la PRIMERA vez que pasa a activa - una campana puede pausarse y
  # reactivarse varias veces, pero "cuantas semanas lleva activa" (panel de
  # estadisticas) cuenta desde su primer arranque, no se reinicia cada vez.
  def marcar_primera_activacion
    return unless estado == 'activa' && estado_changed? && activada_en.nil?

    self.activada_en = Time.current
  end

  def dias_envio_validos
    return if Array(dias_envio).all? { |dia| Cartera::Campanas::LeyCobranza.dia_permitido?(dia) }

    errors.add(:dias_envio, 'solo puede incluir lunes a sabado (Ley 2300 de 2023, art. 3 prohibe domingo)')
  end

  # Cada dia activo en dias_envio debe tener su propia hora exacta de envio
  # en horas_envio, y esa hora debe caer dentro de la ventana legal de ESE
  # dia especifico (Ley 2300 de 2023, art. 3: lun-vie 7-19, sab 8-15).
  # dias_envio_validos ya rechazo dias fuera de 1-6, asi que un dia sin
  # ventana aqui ya quedo reportado por esa otra validacion.
  def horas_envio_validas
    Array(dias_envio).each { |dia| validar_hora_del_dia(dia) }
  end

  def validar_hora_del_dia(dia)
    ventana = Cartera::Campanas::LeyCobranza.ventana_segundos(dia)
    return if ventana.nil?

    nombre_dia = I18n.t('date.day_names')[dia]
    valor = horas_envio[dia.to_s]
    return errors.add(:horas_envio, "falta la hora de envio para el dia #{nombre_dia}") if valor.blank?

    segundos = segundos_desde_medianoche(valor)
    return errors.add(:horas_envio, "la hora de envio del dia #{nombre_dia} no es valida") if segundos.nil?
    return if ventana.cover?(segundos)

    errors.add(:horas_envio,
               "para el dia #{nombre_dia} debe estar entre las #{ventana.first / 3600}:00 y las #{ventana.last / 3600}:00 (Ley 2300 de 2023, art. 3)")
  end

  # base: 10 explicito - Integer("09", exception: false) da nil (no false,
  # nil) porque el 0 inicial se interpreta como prefijo octal y 9 no es un
  # digito octal valido; sin forzar base 10, cualquier hora "08:xx"/"09:xx"
  # se habria rechazado como invalida.
  def segundos_desde_medianoche(valor_hhmm)
    horas, minutos = valor_hhmm.split(':').map { |n| Integer(n, 10, exception: false) }
    return nil if horas.nil? || minutos.nil?

    (horas * 3600) + (minutos * 60)
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

# Borrador de una plantilla de WhatsApp. Solo vive aqui hasta que se envia
# a Twilio (content_sid se asigna en ese momento) - a partir de ahi el
# estado real de aprobacion lo lee channel.content_templates (el espejo
# que mantiene Twilio::TemplateSyncService), nunca duplicado en esta tabla.
# == Schema Information
#
# Table name: cartera_plantillas_whatsapp
#
#  id          :bigint           not null, primary key
#  categoria   :string           not null
#  content_sid :string
#  cuerpo      :text             not null
#  estado      :string           default("borrador"), not null
#  idioma      :string           default("es"), not null
#  nombre      :string           not null
#  tipo        :string           default("text"), not null
#  variables   :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_cartera_plantillas_whatsapp_on_account_id             (account_id)
#  index_cartera_plantillas_whatsapp_on_account_id_and_nombre  (account_id,nombre) UNIQUE
#  index_cartera_plantillas_whatsapp_on_content_sid            (content_sid)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Cartera::PlantillaWhatsapp < ApplicationRecord
  self.table_name = 'cartera_plantillas_whatsapp'

  CATEGORIAS = %w[marketing utility authentication].freeze
  TIPOS = %w[text].freeze

  belongs_to :account

  validates :nombre, :categoria, :tipo, :idioma, :cuerpo, :estado, presence: true
  validates :nombre, uniqueness: { scope: :account_id }
  validates :categoria, inclusion: { in: CATEGORIAS }
  validates :tipo, inclusion: { in: TIPOS }

  def enviada?
    content_sid.present?
  end
end

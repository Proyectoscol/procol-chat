# Plantilla de correo electronico para campanas de cobro. A diferencia de
# las de WhatsApp, no pasa por aprobacion de nadie - vive entera aqui.
# == Schema Information
#
# Table name: cartera_plantillas_email
#
#  id          :bigint           not null, primary key
#  asunto      :string           not null
#  cuerpo_html :text             not null
#  nombre      :string           not null
#  variables   :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_cartera_plantillas_email_on_account_id             (account_id)
#  index_cartera_plantillas_email_on_account_id_and_nombre  (account_id,nombre) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Cartera::PlantillaEmail < ApplicationRecord
  self.table_name = 'cartera_plantillas_email'

  belongs_to :account

  validates :nombre, :asunto, :cuerpo_html, presence: true
  validates :nombre, uniqueness: { scope: :account_id }
end

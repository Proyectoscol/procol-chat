# Paquete descargable (.zip) con TODOS los datos de una cuenta (profesionales,
# servicios, EPS, especialidades, contactos, conversaciones+mensajes+adjuntos,
# citas, lista de espera) para migrarlos a otra instancia -- ver plan de
# migración a producción. Deliberadamente NO incluye automatizaciones
# (disparadores, bot de bienvenida, biblioteca de plantillas, "paciente que
# regresa") -- decisión explícita del usuario, esas se configuran de nuevo en
# cada instancia.
# == Schema Information
#
# Table name: calendario_account_data_exports
#
#  id            :bigint           not null, primary key
#  error_message :text
#  manifest      :jsonb            not null
#  status        :integer          default("pending"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_calendario_account_data_exports_on_account_id     (account_id)
#  index_calendario_account_data_exports_on_created_by_id  (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class Calendario::AccountDataExport < ApplicationRecord
  self.table_name = 'calendario_account_data_exports'

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_one_attached :export_file

  after_create_commit :enqueue_export_job

  private

  def enqueue_export_job
    Calendario::AccountDataExportJob.perform_later(id)
  end
end

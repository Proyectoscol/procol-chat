# Paquete descargable (.zip) con TODOS los datos de una cuenta (profesionales,
# servicios, EPS, especialidades, contactos, conversaciones+mensajes+adjuntos,
# citas, lista de espera) para migrarlos a otra instancia -- ver plan de
# migración a producción. Deliberadamente NO incluye automatizaciones
# (disparadores, bot de bienvenida, biblioteca de plantillas, "paciente que
# regresa") -- decisión explícita del usuario, esas se configuran de nuevo en
# cada instancia.
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

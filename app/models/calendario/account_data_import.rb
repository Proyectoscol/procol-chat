# Importa un .zip generado por Calendario::AccountDataExport dentro de ESTA
# cuenta -- siempre aditivo, nunca borra nada existente. Requiere elegir una
# bandeja (inbox) de destino: todas las conversaciones/mensajes importados se
# asocian a esa bandeja (pensado para apuntar a la bandeja real de WhatsApp
# de producción antes de que empiece a recibir tráfico real -- ver plan de
# migración).
class Calendario::AccountDataImport < ApplicationRecord
  self.table_name = 'calendario_account_data_imports'

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :inbox
  has_one_attached :import_file

  after_create_commit :enqueue_import_job

  private

  # Espera un poco antes de arrancar -- igual que Import::WhatsappChatBatch,
  # el archivo todavia puede estar subiendose al storage en el momento del commit.
  def enqueue_import_job
    Calendario::AccountDataImportJob.set(wait: 10.seconds).perform_later(id)
  end
end

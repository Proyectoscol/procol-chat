# == Schema Information
#
# Table name: import_whatsapp_chat_batches
#
#  id                :bigint           not null, primary key
#  error_message     :text
#  original_filename :string
#  phone_number      :string           not null
#  stats             :jsonb            not null
#  status            :integer          default("pending"), not null
#  us_sender_name    :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  contact_id        :bigint
#  created_by_id     :bigint
#  inbox_id          :bigint           not null
#
# Indexes
#
#  index_import_whatsapp_chat_batches_on_account_id     (account_id)
#  index_import_whatsapp_chat_batches_on_contact_id     (contact_id)
#  index_import_whatsapp_chat_batches_on_created_by_id  (created_by_id)
#  index_import_whatsapp_chat_batches_on_inbox_id       (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#
class Import::WhatsappChatBatch < ApplicationRecord
  self.table_name = 'import_whatsapp_chat_batches'

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3, needs_review: 4 }

  belongs_to :account
  belongs_to :inbox
  belongs_to :contact, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_one_attached :zip_file

  validates :us_sender_name, :phone_number, presence: true

  after_create_commit :enqueue_import_job

  private

  # Espera un poco antes de arrancar -- igual que DataImport (ver
  # app/models/data_import.rb), el archivo todavia puede estar subiendose al
  # storage en la nube en el momento del commit.
  def enqueue_import_job
    Import::WhatsappChatImportJob.set(wait: 10.seconds).perform_later(id)
  end
end

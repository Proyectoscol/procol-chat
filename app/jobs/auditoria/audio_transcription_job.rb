class Auditoria::AudioTranscriptionJob < ApplicationJob
  queue_as :low

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    audio_attachment = message.attachments.find_by(file_type: :audio)
    return if audio_attachment.blank?
    return if audio_attachment.meta['transcribed_text'].present?

    result = Auditoria::AudioTranscriptionService.new(account: message.account, message: message).perform
    return unless result[:error]

    Rails.logger.error(
      "[Auditoria] audio transcription failed for message=#{message_id} account=#{message.account_id}: #{result[:error]}"
    )
  end
end

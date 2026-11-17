/* global axios */
import ApiClient from './ApiClient';

class ImportWhatsappChatBatchesAPI extends ApiClient {
  constructor() {
    super('import/whatsapp_chat_batches', { accountScoped: true });
  }

  create({ zipFile, inboxId, usSenderName, phoneNumber, originalFilename }) {
    const formData = new FormData();
    formData.append('zip_file', zipFile);
    formData.append('inbox_id', inboxId);
    formData.append('us_sender_name', usSenderName);
    formData.append('phone_number', phoneNumber);
    formData.append('original_filename', originalFilename);
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new ImportWhatsappChatBatchesAPI();

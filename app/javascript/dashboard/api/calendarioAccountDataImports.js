/* global axios */
import ApiClient from './ApiClient';

class CalendarioAccountDataImportsAPI extends ApiClient {
  constructor() {
    super('calendario/account_data_imports', { accountScoped: true });
  }

  create({ importFile, inboxId }) {
    const formData = new FormData();
    formData.append('import_file', importFile);
    formData.append('inbox_id', inboxId);
    return axios.post(this.url, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new CalendarioAccountDataImportsAPI();

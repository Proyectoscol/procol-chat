/* global axios */
import ApiClient from './ApiClient';

class CalendarioMessageTemplatesAPI extends ApiClient {
  constructor() {
    super('calendario/message_templates', { accountScoped: true });
  }

  activate(id) {
    return axios.post(`${this.url}/${id}/activate`);
  }
}

export default new CalendarioMessageTemplatesAPI();

/* global axios */
import ApiClient from './ApiClient';

class CalendarioContactCreditsAPI extends ApiClient {
  constructor() {
    super('calendario/contact_credits', { accountScoped: true });
  }

  getForContact(contactId) {
    return axios.get(this.url, { params: { contact_id: contactId } });
  }
}

export default new CalendarioContactCreditsAPI();

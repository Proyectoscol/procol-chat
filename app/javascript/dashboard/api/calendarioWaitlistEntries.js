/* global axios */
import ApiClient from './ApiClient';

class CalendarioWaitlistEntriesAPI extends ApiClient {
  constructor() {
    super('calendario/waitlist_entries', { accountScoped: true });
  }

  get({ professionalId } = {}) {
    return axios.get(this.url, { params: { professional_id: professionalId } });
  }
}

export default new CalendarioWaitlistEntriesAPI();

/* global axios */
import ApiClient from './ApiClient';

class CalendarioWaitlistEntriesAPI extends ApiClient {
  constructor() {
    super('calendario/waitlist_entries', { accountScoped: true });
  }

  get({ professionalId } = {}) {
    return axios.get(this.url, { params: { professional_id: professionalId } });
  }

  checkDuplicate({ contactId, professionalId, serviceId }) {
    return axios.get(`${this.url}/check_duplicate`, {
      params: {
        contact_id: contactId,
        professional_id: professionalId,
        service_id: serviceId,
      },
    });
  }
}

export default new CalendarioWaitlistEntriesAPI();

/* global axios */
import ApiClient from './ApiClient';

class CalendarioOpenDaysAPI extends ApiClient {
  constructor() {
    super('calendario/open_days', { accountScoped: true });
  }

  get({ professionalId } = {}) {
    return axios.get(this.url, { params: { professional_id: professionalId } });
  }
}

export default new CalendarioOpenDaysAPI();

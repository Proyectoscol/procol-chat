/* global axios */
import ApiClient from './ApiClient';

class CalendarioStatsAPI extends ApiClient {
  constructor() {
    super('calendario/stats', { accountScoped: true });
  }

  get({ since, until, professionalId, groupBy }) {
    return axios.get(this.url, {
      params: {
        since,
        until,
        professional_id: professionalId,
        group_by: groupBy,
      },
    });
  }
}

export default new CalendarioStatsAPI();

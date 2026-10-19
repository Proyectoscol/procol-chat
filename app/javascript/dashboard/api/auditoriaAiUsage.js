/* global axios */
import ApiClient from './ApiClient';

class AuditoriaAiUsageAPI extends ApiClient {
  constructor() {
    super('auditoria/ai_usage', { accountScoped: true });
  }

  getSummary() {
    return axios.get(`${this.url}/summary`);
  }

  getLogs(page = 1) {
    return axios.get(this.url, { params: { page } });
  }

  updateSettings(data) {
    return axios.patch(`${this.url}/settings`, data);
  }
}

export default new AuditoriaAiUsageAPI();

/* global axios */
import ApiClient from './ApiClient';

class CalendarioProfessionalAvailabilitiesAPI extends ApiClient {
  constructor() {
    super('calendario/professionals', { accountScoped: true });
  }

  get(professionalId) {
    return axios.get(`${this.url}/${professionalId}/availabilities`);
  }

  create(professionalId, data) {
    return axios.post(`${this.url}/${professionalId}/availabilities`, data);
  }

  delete(professionalId, id) {
    return axios.delete(`${this.url}/${professionalId}/availabilities/${id}`);
  }
}

export default new CalendarioProfessionalAvailabilitiesAPI();

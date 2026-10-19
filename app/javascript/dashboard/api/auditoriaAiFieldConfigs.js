/* global axios */
import ApiClient from './ApiClient';

class AuditoriaAiFieldConfigsAPI extends ApiClient {
  constructor() {
    super('auditoria/ai_field_configs', { accountScoped: true });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { ai_field_config: data });
  }
}

export default new AuditoriaAiFieldConfigsAPI();

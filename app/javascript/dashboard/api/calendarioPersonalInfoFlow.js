/* global axios */
import ApiClient from './ApiClient';

class CalendarioPersonalInfoFlowAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  create(conversationId) {
    return axios.post(
      `${this.url}/${conversationId}/personal_info_flow_request`
    );
  }
}

export default new CalendarioPersonalInfoFlowAPI();

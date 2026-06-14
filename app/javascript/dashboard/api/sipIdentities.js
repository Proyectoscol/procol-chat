/* global axios */
import ApiClient from './ApiClient';

class SipIdentitiesAPI extends ApiClient {
  constructor() {
    super('sip/identities', { accountScoped: true });
  }

  update(agentId, params) {
    return axios.patch(`${this.url}/${agentId}`, params);
  }
}

export default new SipIdentitiesAPI();

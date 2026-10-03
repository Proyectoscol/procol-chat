/* global axios */
import ApiClient from '../ApiClient';

class CarteraSyncAPI extends ApiClient {
  constructor() {
    super('cartera/syncs', { accountScoped: true });
  }

  create() {
    return axios.post(this.url);
  }
}

export default new CarteraSyncAPI();

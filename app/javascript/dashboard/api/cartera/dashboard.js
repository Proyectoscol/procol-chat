/* global axios */
import ApiClient from '../ApiClient';

class CarteraDashboardAPI extends ApiClient {
  constructor() {
    super('cartera/dashboard', { accountScoped: true });
  }

  get(params = {}) {
    const { sucursal, meses } = params;
    const query = new URLSearchParams(
      Object.entries({ sucursal, meses }).filter(
        ([, v]) => v !== undefined && v !== ''
      )
    ).toString();
    return axios.get(`${this.url}${query ? `?${query}` : ''}`);
  }
}

export default new CarteraDashboardAPI();

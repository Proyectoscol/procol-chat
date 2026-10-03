/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== ''
    )
  ).toString();

class CarteraFacturaAPI extends ApiClient {
  constructor() {
    super('cartera/facturas', { accountScoped: true });
  }

  get(params = {}) {
    const { page = 1, tramo, clienteId, sortBy, sortDir } = params;
    return axios.get(
      `${this.url}?${buildParams({ page, tramo, cliente_id: clienteId, sort_by: sortBy, sort_dir: sortDir })}`
    );
  }
}

export default new CarteraFacturaAPI();

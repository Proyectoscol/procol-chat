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
    const {
      page = 1,
      pageSize,
      tramo,
      estado,
      clienteId,
      sortBy,
      sortDir,
    } = params;
    return axios.get(
      `${this.url}?${buildParams({ page, page_size: pageSize, tramo, estado, cliente_id: clienteId, sort_by: sortBy, sort_dir: sortDir })}`
    );
  }

  exportUrl(params = {}) {
    const { tramo, estado, clienteId, sortBy, sortDir } = params;
    const query = buildParams({
      tramo,
      estado,
      cliente_id: clienteId,
      sort_by: sortBy,
      sort_dir: sortDir,
    });
    return `${this.url}/export${query ? `?${query}` : ''}`;
  }
}

export default new CarteraFacturaAPI();

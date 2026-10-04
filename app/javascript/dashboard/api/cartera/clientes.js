/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== ''
    )
  ).toString();

class CarteraClienteAPI extends ApiClient {
  constructor() {
    super('cartera/clientes', { accountScoped: true });
  }

  get(params = {}) {
    const { page = 1, pageSize, sortBy, sortDir } = params;
    return axios.get(
      `${this.url}?${buildParams({ page, page_size: pageSize, sort_by: sortBy, sort_dir: sortDir })}`
    );
  }

  search(query = '') {
    return axios.get(`${this.url}/search?${buildParams({ q: query })}`);
  }

  exportUrl(params = {}) {
    const { sortBy, sortDir } = params;
    const query = buildParams({ sort_by: sortBy, sort_dir: sortDir });
    return `${this.url}/export${query ? `?${query}` : ''}`;
  }
}

export default new CarteraClienteAPI();

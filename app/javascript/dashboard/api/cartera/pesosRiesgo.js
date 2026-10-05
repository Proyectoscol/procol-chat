/* global axios */
import ApiClient from '../ApiClient';

// Recurso singular (resource, no resources): una fila de pesos por cuenta.
class CarteraPesosRiesgoAPI extends ApiClient {
  constructor() {
    super('cartera/pesos_riesgo', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  update(pesos) {
    return axios.put(this.url, { pesos });
  }
}

export default new CarteraPesosRiesgoAPI();

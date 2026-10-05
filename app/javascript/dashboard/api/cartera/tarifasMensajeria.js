/* global axios */
import ApiClient from '../ApiClient';

// Recurso singular (resource, no resources): una fila de tarifario por cuenta.
class CarteraTarifasMensajeriaAPI extends ApiClient {
  constructor() {
    super('cartera/tarifas_mensajeria', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  update(tarifas) {
    return axios.put(this.url, { tarifas });
  }
}

export default new CarteraTarifasMensajeriaAPI();

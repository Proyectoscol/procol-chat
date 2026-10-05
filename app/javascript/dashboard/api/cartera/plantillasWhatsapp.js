/* global axios */
import ApiClient from '../ApiClient';

class CarteraPlantillaWhatsappAPI extends ApiClient {
  constructor() {
    super('cartera/plantillas_whatsapp', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  create(plantilla) {
    return axios.post(this.url, { plantilla });
  }

  solicitarAprobacion(id) {
    return axios.post(`${this.url}/${id}/solicitar_aprobacion`);
  }
}

export default new CarteraPlantillaWhatsappAPI();

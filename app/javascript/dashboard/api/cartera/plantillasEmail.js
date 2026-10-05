/* global axios */
import ApiClient from '../ApiClient';

class CarteraPlantillaEmailAPI extends ApiClient {
  constructor() {
    super('cartera/plantillas_email', { accountScoped: true });
  }

  create(plantilla) {
    return axios.post(this.url, { plantilla });
  }

  update(id, plantilla) {
    return axios.patch(`${this.url}/${id}`, { plantilla });
  }
}

export default new CarteraPlantillaEmailAPI();

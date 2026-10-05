/* global axios */
import ApiClient from '../ApiClient';

class CarteraCampanaAPI extends ApiClient {
  constructor() {
    super('cartera/campanas', { accountScoped: true });
  }

  update(id, campana) {
    return axios.patch(`${this.url}/${id}`, { campana });
  }

  create(campana) {
    return axios.post(this.url, { campana });
  }

  simular(id) {
    return axios.post(`${this.url}/${id}/simulacion`);
  }

  probar(id) {
    return axios.post(`${this.url}/${id}/prueba`);
  }

  getEstadisticas(id) {
    return axios.get(`${this.url}/${id}/estadisticas`);
  }

  // --- reglas, anidadas bajo una campana ---

  getReglas(campanaId) {
    return axios.get(`${this.url}/${campanaId}/reglas`);
  }

  createRegla(campanaId, regla) {
    return axios.post(`${this.url}/${campanaId}/reglas`, { regla });
  }

  updateRegla(campanaId, reglaId, regla) {
    return axios.patch(`${this.url}/${campanaId}/reglas/${reglaId}`, {
      regla,
    });
  }

  deleteRegla(campanaId, reglaId) {
    return axios.delete(`${this.url}/${campanaId}/reglas/${reglaId}`);
  }

  getEnvios(campanaId) {
    return axios.get(`${this.url}/${campanaId}/envios`);
  }
}

export default new CarteraCampanaAPI();

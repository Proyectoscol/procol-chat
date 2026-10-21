/* global axios */

import ApiClient from './ApiClient';

const buildAgentFormData = data => {
  const formData = new FormData();
  Object.entries(data || {}).forEach(([key, value]) => {
    if (value === undefined || value === null) return;

    // multipart no tiene forma nativa de mandar un arreglo vacio -- un
    // placeholder en blanco mantiene la clave presente (el backend filtra
    // blancos) para poder "limpiar" restricted_inbox_ids enviando [].
    if (Array.isArray(value)) {
      if (value.length === 0) {
        formData.append(`agent[${key}][]`, '');
      } else {
        value.forEach(item => formData.append(`agent[${key}][]`, item));
      }
      return;
    }

    formData.append(`agent[${key}]`, value);
  });
  return formData;
};

class Agents extends ApiClient {
  constructor() {
    super('agents', { accountScoped: true });
  }

  bulkInvite({ emails }) {
    return axios.post(`${this.url}/bulk_create`, {
      emails,
    });
  }

  create(data) {
    return axios.post(this.url, buildAgentFormData(data), {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, buildAgentFormData(data), {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  deleteAvatar(id) {
    return axios.delete(`${this.url}/${id}/avatar`);
  }

  resetPassword(id, password) {
    return axios.patch(`${this.url}/${id}/reset_password`, { password });
  }
}

export default new Agents();

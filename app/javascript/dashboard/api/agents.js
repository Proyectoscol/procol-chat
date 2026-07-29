/* global axios */

import ApiClient from './ApiClient';

const buildAgentFormData = data => {
  const formData = new FormData();
  Object.entries(data || {}).forEach(([key, value]) => {
    if (value !== undefined && value !== null) {
      formData.append(`agent[${key}]`, value);
    }
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
}

export default new Agents();

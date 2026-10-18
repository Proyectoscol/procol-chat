/* global axios */
import ApiClient from './ApiClient';

class AuditoriaConversationAnalysesAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  getAnalysis(conversationId) {
    return axios.get(`${this.url}/${conversationId}/conversation_analyses`);
  }

  createAnalysis(conversationId) {
    return axios.post(`${this.url}/${conversationId}/conversation_analyses`);
  }
}

export default new AuditoriaConversationAnalysesAPI();

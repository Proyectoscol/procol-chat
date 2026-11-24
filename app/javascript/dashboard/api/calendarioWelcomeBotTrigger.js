/* global axios */
import ApiClient from './ApiClient';

class CalendarioWelcomeBotTriggerAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  create({ conversationId, welcomeBotFlowId }) {
    return axios.post(`${this.url}/${conversationId}/welcome_bot_trigger`, {
      welcome_bot_flow_id: welcomeBotFlowId,
    });
  }
}

export default new CalendarioWelcomeBotTriggerAPI();

import ApiClient from './ApiClient';

class CalendarioWelcomeBotFlowsAPI extends ApiClient {
  constructor() {
    super('calendario/welcome_bot_flows', { accountScoped: true });
  }
}

export default new CalendarioWelcomeBotFlowsAPI();

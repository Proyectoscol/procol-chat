import ApiClient from './ApiClient';

class CalendarioPayersAPI extends ApiClient {
  constructor() {
    super('calendario/payers', { accountScoped: true });
  }
}

export default new CalendarioPayersAPI();

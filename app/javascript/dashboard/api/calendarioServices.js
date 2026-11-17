import ApiClient from './ApiClient';

class CalendarioServicesAPI extends ApiClient {
  constructor() {
    super('calendario/services', { accountScoped: true });
  }
}

export default new CalendarioServicesAPI();

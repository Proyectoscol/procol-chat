import ApiClient from './ApiClient';

class CalendarioProfessionalsAPI extends ApiClient {
  constructor() {
    super('calendario/professionals', { accountScoped: true });
  }
}

export default new CalendarioProfessionalsAPI();

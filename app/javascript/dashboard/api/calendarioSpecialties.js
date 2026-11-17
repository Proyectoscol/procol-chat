import ApiClient from './ApiClient';

class CalendarioSpecialtiesAPI extends ApiClient {
  constructor() {
    super('calendario/specialties', { accountScoped: true });
  }
}

export default new CalendarioSpecialtiesAPI();

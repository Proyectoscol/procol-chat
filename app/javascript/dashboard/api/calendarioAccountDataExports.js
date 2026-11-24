import ApiClient from './ApiClient';

class CalendarioAccountDataExportsAPI extends ApiClient {
  constructor() {
    super('calendario/account_data_exports', { accountScoped: true });
  }
}

export default new CalendarioAccountDataExportsAPI();

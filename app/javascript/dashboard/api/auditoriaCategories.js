import ApiClient from './ApiClient';

class AuditoriaCategoriesAPI extends ApiClient {
  constructor() {
    super('auditoria/categories', { accountScoped: true });
  }
}

export default new AuditoriaCategoriesAPI();

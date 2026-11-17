import ApiClient from './ApiClient';

class CalendarioAppointmentEventTriggersAPI extends ApiClient {
  constructor() {
    super('calendario/appointment_event_triggers', { accountScoped: true });
  }
}

export default new CalendarioAppointmentEventTriggersAPI();

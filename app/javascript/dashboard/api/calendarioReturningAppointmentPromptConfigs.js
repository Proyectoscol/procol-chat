import ApiClient from './ApiClient';

class CalendarioReturningAppointmentPromptConfigsAPI extends ApiClient {
  constructor() {
    super('calendario/returning_appointment_prompt_configs', {
      accountScoped: true,
    });
  }
}

export default new CalendarioReturningAppointmentPromptConfigsAPI();

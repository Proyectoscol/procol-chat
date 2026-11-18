/* global axios */
import ApiClient from './ApiClient';

class CalendarioAppointmentsAPI extends ApiClient {
  constructor() {
    super('calendario/appointments', { accountScoped: true });
  }

  getRange({ since, until, professionalId } = {}) {
    return axios.get(this.url, {
      params: { since, until, professional_id: professionalId },
    });
  }

  getByCreatedRange({ createdSince, createdUntil, professionalId } = {}) {
    return axios.get(this.url, {
      params: {
        created_since: createdSince,
        created_until: createdUntil,
        professional_id: professionalId,
      },
    });
  }

  getAgenda(date = null) {
    return axios.get(`${this.url}/agenda`, { params: { date } });
  }

  getNextAgendaDate() {
    return axios.get(`${this.url}/next_agenda_date`);
  }

  getByContact(contactId) {
    return axios.get(this.url, { params: { contact_id: contactId } });
  }
}

export default new CalendarioAppointmentsAPI();

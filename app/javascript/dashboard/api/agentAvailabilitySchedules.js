import ApiClient from './ApiClient';

class AgentAvailabilitySchedules extends ApiClient {
  constructor() {
    super('agent_availability_schedules', { accountScoped: true });
  }
}

export default new AgentAvailabilitySchedules();

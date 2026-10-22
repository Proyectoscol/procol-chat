/* global axios */
import ApiClient from './ApiClient';

class AuditoriaDailyJobsAPI extends ApiClient {
  constructor() {
    super('auditoria/daily_jobs', { accountScoped: true });
  }

  runConversationAnalysis() {
    return axios.post(`${this.url}/run_conversation_analysis`);
  }

  runAdvisorRollup(summaryDate) {
    return axios.post(`${this.url}/run_advisor_rollup`, {
      summary_date: summaryDate || undefined,
    });
  }

  getBacklogEstimate() {
    return axios.get(`${this.url}/backlog_estimate`);
  }

  runFullBacklog() {
    return axios.post(`${this.url}/run_full_backlog`);
  }
}

export default new AuditoriaDailyJobsAPI();

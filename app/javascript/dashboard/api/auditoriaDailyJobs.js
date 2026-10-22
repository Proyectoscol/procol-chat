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
}

export default new AuditoriaDailyJobsAPI();

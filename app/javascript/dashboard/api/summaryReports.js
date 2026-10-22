/* global axios */
import ApiClient from './ApiClient';

class SummaryReportsAPI extends ApiClient {
  constructor() {
    super('summary_reports', { accountScoped: true, apiVersion: 'v2' });
  }

  getTeamReports({ since, until, businessHours } = {}) {
    return axios.get(`${this.url}/team`, {
      params: {
        since,
        until,
        business_hours: businessHours,
      },
    });
  }

  getAgentReports({ since, until, businessHours } = {}) {
    return axios.get(`${this.url}/agent`, {
      params: {
        since,
        until,
        business_hours: businessHours,
      },
    });
  }

  getInboxReports({ since, until, businessHours } = {}) {
    return axios.get(`${this.url}/inbox`, {
      params: {
        since,
        until,
        business_hours: businessHours,
      },
    });
  }

  getLabelReports({ since, until, businessHours } = {}) {
    return axios.get(`${this.url}/label`, {
      params: {
        since,
        until,
        business_hours: businessHours,
      },
    });
  }

  getAuditoriaAdvisorReports({ since, until, inboxId, sameDayOnly } = {}) {
    return axios.get(`${this.url}/auditoria_advisor`, {
      params: {
        since,
        until,
        inbox_id: inboxId,
        same_day_only: sameDayOnly,
      },
    });
  }

  getAuditoriaAdvisorConversations({
    since,
    until,
    inboxId,
    userId,
    page,
    signal,
  } = {}) {
    return axios.get(`${this.url}/auditoria_advisor_conversations`, {
      params: {
        since,
        until,
        inbox_id: inboxId,
        user_id: userId,
        page,
      },
      signal,
    });
  }

  getAuditoriaCategoryReports({ since, until, inboxId, countMode } = {}) {
    return axios.get(`${this.url}/auditoria_category`, {
      params: {
        since,
        until,
        inbox_id: inboxId,
        count_mode: countMode,
      },
    });
  }

  getAuditoriaCategoryTimeseries({
    since,
    until,
    inboxId,
    categoryIds,
    countMode,
  } = {}) {
    return axios.get(`${this.url}/auditoria_category_timeseries`, {
      params: {
        since,
        until,
        inbox_id: inboxId,
        category_ids: categoryIds,
        count_mode: countMode,
      },
    });
  }

  getAuditoriaCategoryConversations({
    since,
    until,
    categoryId,
    inboxId,
    page,
    signal,
  } = {}) {
    return axios.get(`${this.url}/auditoria_category_conversations`, {
      params: {
        since,
        until,
        category_id: categoryId,
        inbox_id: inboxId,
        page,
      },
      signal,
    });
  }

  getAuditoriaAdvisorDailyRollup({ since, until, inboxId, userId } = {}) {
    return axios.get(`${this.url}/auditoria_advisor_daily_rollup`, {
      params: {
        since,
        until,
        inbox_id: inboxId,
        user_id: userId,
      },
    });
  }

  getAuditoriaCategoryTerms({
    since,
    until,
    categoryId,
    inboxId,
    countMode,
  } = {}) {
    return axios.get(`${this.url}/auditoria_category_terms`, {
      params: {
        since,
        until,
        category_id: categoryId,
        inbox_id: inboxId,
        count_mode: countMode,
      },
    });
  }
}

export default new SummaryReportsAPI();

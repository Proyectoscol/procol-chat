import SummaryReportsAPI from 'dashboard/api/summaryReports';
import camelcaseKeys from 'camelcase-keys';

const typeMap = {
  inbox: {
    flagKey: 'isFetchingInboxSummaryReports',
    apiMethod: 'getInboxReports',
    mutationKey: 'setInboxSummaryReport',
  },
  agent: {
    flagKey: 'isFetchingAgentSummaryReports',
    apiMethod: 'getAgentReports',
    mutationKey: 'setAgentSummaryReport',
  },
  team: {
    flagKey: 'isFetchingTeamSummaryReports',
    apiMethod: 'getTeamReports',
    mutationKey: 'setTeamSummaryReport',
  },
  label: {
    flagKey: 'isFetchingLabelSummaryReports',
    apiMethod: 'getLabelReports',
    mutationKey: 'setLabelSummaryReport',
  },
  auditoriaAdvisor: {
    flagKey: 'isFetchingAuditoriaAdvisorSummaryReports',
    apiMethod: 'getAuditoriaAdvisorReports',
    mutationKey: 'setAuditoriaAdvisorSummaryReport',
  },
  auditoriaCategory: {
    flagKey: 'isFetchingAuditoriaCategorySummaryReports',
    apiMethod: 'getAuditoriaCategoryReports',
    mutationKey: 'setAuditoriaCategorySummaryReport',
  },
  auditoriaCategoryTimeseries: {
    flagKey: 'isFetchingAuditoriaCategoryTimeseries',
    apiMethod: 'getAuditoriaCategoryTimeseries',
    mutationKey: 'setAuditoriaCategoryTimeseries',
  },
};

async function fetchSummaryReports(type, params, { commit }) {
  const config = typeMap[type];
  if (!config) return;

  let error = null;
  try {
    commit('setUIFlags', { [config.flagKey]: true });
    const response = await SummaryReportsAPI[config.apiMethod](params);
    commit(config.mutationKey, camelcaseKeys(response.data, { deep: true }));
  } catch (e) {
    error = e;
  } finally {
    commit('setUIFlags', { [config.flagKey]: false });
  }
  if (error) throw error;
}

export const initialState = {
  inboxSummaryReports: [],
  agentSummaryReports: [],
  teamSummaryReports: [],
  labelSummaryReports: [],
  auditoriaAdvisorSummaryReports: [],
  auditoriaAdvisorSummaryTotals: null,
  auditoriaCategorySummaryReports: [],
  auditoriaCategorySummaryTotals: null,
  auditoriaCategoryTimeseries: [],
  uiFlags: {
    isFetchingInboxSummaryReports: false,
    isFetchingAgentSummaryReports: false,
    isFetchingTeamSummaryReports: false,
    isFetchingLabelSummaryReports: false,
    isFetchingAuditoriaAdvisorSummaryReports: false,
    isFetchingAuditoriaCategorySummaryReports: false,
    isFetchingAuditoriaCategoryTimeseries: false,
  },
};

export const getters = {
  getInboxSummaryReports(state) {
    return state.inboxSummaryReports;
  },
  getAgentSummaryReports(state) {
    return state.agentSummaryReports;
  },
  getTeamSummaryReports(state) {
    return state.teamSummaryReports;
  },
  getLabelSummaryReports(state) {
    return state.labelSummaryReports;
  },
  getAuditoriaAdvisorSummaryReports(state) {
    return state.auditoriaAdvisorSummaryReports;
  },
  getAuditoriaAdvisorSummaryTotals(state) {
    return state.auditoriaAdvisorSummaryTotals;
  },
  getAuditoriaCategorySummaryReports(state) {
    return state.auditoriaCategorySummaryReports;
  },
  getAuditoriaCategorySummaryTotals(state) {
    return state.auditoriaCategorySummaryTotals;
  },
  getAuditoriaCategoryTimeseries(state) {
    return state.auditoriaCategoryTimeseries;
  },
  getUIFlags(state) {
    return state.uiFlags;
  },
};

export const actions = {
  fetchInboxSummaryReports({ commit }, params) {
    return fetchSummaryReports('inbox', params, { commit });
  },

  fetchAgentSummaryReports({ commit }, params) {
    return fetchSummaryReports('agent', params, { commit });
  },

  fetchTeamSummaryReports({ commit }, params) {
    return fetchSummaryReports('team', params, { commit });
  },

  fetchLabelSummaryReports({ commit }, params) {
    return fetchSummaryReports('label', params, { commit });
  },

  fetchAuditoriaAdvisorSummaryReports({ commit }, params) {
    return fetchSummaryReports('auditoriaAdvisor', params, { commit });
  },

  fetchAuditoriaCategorySummaryReports({ commit }, params) {
    return fetchSummaryReports('auditoriaCategory', params, { commit });
  },

  fetchAuditoriaCategoryTimeseries({ commit }, params) {
    return fetchSummaryReports('auditoriaCategoryTimeseries', params, {
      commit,
    });
  },
};

export const mutations = {
  setInboxSummaryReport(state, data) {
    state.inboxSummaryReports = data;
  },
  setAgentSummaryReport(state, data) {
    state.agentSummaryReports = data;
  },
  setTeamSummaryReport(state, data) {
    state.teamSummaryReports = data;
  },
  setLabelSummaryReport(state, data) {
    state.labelSummaryReports = data;
  },
  // El endpoint devuelve { advisors, totals } (no una lista plana como los
  // demas reportes) porque ademas de las filas por asesor trae el total y
  // el promedio general ya calculados sobre el mismo scope filtrado.
  setAuditoriaAdvisorSummaryReport(state, data) {
    state.auditoriaAdvisorSummaryReports = data.advisors || [];
    state.auditoriaAdvisorSummaryTotals = data.totals || null;
  },
  setAuditoriaCategorySummaryReport(state, data) {
    state.auditoriaCategorySummaryReports = data.categories || [];
    state.auditoriaCategorySummaryTotals = data.totals || null;
  },
  // El endpoint devuelve { series } -- un arreglo de {id, title, points},
  // no una lista plana -- cada categoria ya trae sus propios puntos
  // {date, count} listos para el chart.
  setAuditoriaCategoryTimeseries(state, data) {
    state.auditoriaCategoryTimeseries = data.series || [];
  },
  setUIFlags(state, uiFlag) {
    state.uiFlags = { ...state.uiFlags, ...uiFlag };
  },
};

export default {
  namespaced: true,
  state: initialState,
  getters,
  actions,
  mutations,
};

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
  // skipCamelCase: category_counts trae titulos de categoria en texto
  // libre como KEYS del hash (ej. "Tiempo de decision") -- camelcaseKeys
  // deep:true los mutila (los espacios se vuelven camelCase:
  // "tiempoDeDecision"). El resto de tipos en este mapa solo tienen
  // nombres de columna conocidos como keys, nunca texto libre del usuario.
  auditoriaAdvisorDailyRollup: {
    flagKey: 'isFetchingAuditoriaAdvisorDailyRollup',
    apiMethod: 'getAuditoriaAdvisorDailyRollup',
    mutationKey: 'setAuditoriaAdvisorDailyRollup',
    skipCamelCase: true,
  },
};

async function fetchSummaryReports(type, params, { commit }) {
  const config = typeMap[type];
  if (!config) return;

  let error = null;
  try {
    commit('setUIFlags', { [config.flagKey]: true });
    const response = await SummaryReportsAPI[config.apiMethod](params);
    const payload = config.skipCamelCase
      ? response.data
      : camelcaseKeys(response.data, { deep: true });
    commit(config.mutationKey, payload);
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
  auditoriaCategoryTimeseriesBucket: 'day',
  auditoriaAdvisorDailyRollupSummaries: [],
  uiFlags: {
    isFetchingInboxSummaryReports: false,
    isFetchingAgentSummaryReports: false,
    isFetchingTeamSummaryReports: false,
    isFetchingLabelSummaryReports: false,
    isFetchingAuditoriaAdvisorSummaryReports: false,
    isFetchingAuditoriaCategorySummaryReports: false,
    isFetchingAuditoriaCategoryTimeseries: false,
    isFetchingAuditoriaAdvisorDailyRollup: false,
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
  getAuditoriaCategoryTimeseriesBucket(state) {
    return state.auditoriaCategoryTimeseriesBucket;
  },
  getAuditoriaAdvisorDailyRollupSummaries(state) {
    return state.auditoriaAdvisorDailyRollupSummaries;
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

  fetchAuditoriaAdvisorDailyRollup({ commit }, params) {
    return fetchSummaryReports('auditoriaAdvisorDailyRollup', params, {
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
    state.auditoriaCategoryTimeseriesBucket = data.bucket || 'day';
  },
  // El endpoint devuelve { summaries } (no una lista plana) -- cada fila ya
  // es un resumen completo (asesor + dia + narrativa), sin totales
  // agregados como el reporte de advisors en vivo. Transform manual (no
  // camelcaseKeys, ver skipCamelCase arriba): category_counts se deja tal
  // cual, solo se transforman los campos que SI son nombres de columna.
  setAuditoriaAdvisorDailyRollup(state, data) {
    state.auditoriaAdvisorDailyRollupSummaries = (data.summaries || []).map(
      row => ({
        userId: row.user_id,
        summaryDate: row.summary_date,
        conversationsCount: row.conversations_count,
        categoryCounts: row.category_counts || {},
        feedbackTagsPositive: row.feedback_tags_positive || [],
        feedbackTagsNegative: row.feedback_tags_negative || [],
        feedbackTagsNegativeDetail: (
          row.feedback_tags_negative_detail || []
        ).map(detail => ({
          tag: detail.tag,
          reason: detail.reason,
          conversationIds: detail.conversation_ids || [],
        })),
        generatedAt: row.generated_at,
        results: row.results
          ? {
              summary: row.results.summary,
              shortFeedback: row.results.short_feedback,
              shortFeedbackReason: row.results.short_feedback_reason,
              toneOverview: row.results.tone_overview,
              recommendation: row.results.recommendation,
            }
          : null,
      })
    );
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

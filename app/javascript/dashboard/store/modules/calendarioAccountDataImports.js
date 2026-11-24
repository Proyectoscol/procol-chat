import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioAccountDataImportsAPI from '../../api/calendarioAccountDataImports';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
  },
};

export const getters = {
  getImports(_state) {
    return _state.records;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit('setUIFlags', { isFetching: true });
    try {
      const response = await CalendarioAccountDataImportsAPI.get();
      commit('setImports', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    const response = await CalendarioAccountDataImportsAPI.create(data);
    commit('addImport', response.data);
    return response.data;
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setImports: MutationHelpers.set,
  addImport: MutationHelpers.create,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

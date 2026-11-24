import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioAccountDataExportsAPI from '../../api/calendarioAccountDataExports';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
  },
};

export const getters = {
  getExports(_state) {
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
      const response = await CalendarioAccountDataExportsAPI.get();
      commit('setExports', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }) => {
    const response = await CalendarioAccountDataExportsAPI.create();
    commit('addExport', response.data);
    return response.data;
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setExports: MutationHelpers.set,
  addExport: MutationHelpers.create,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

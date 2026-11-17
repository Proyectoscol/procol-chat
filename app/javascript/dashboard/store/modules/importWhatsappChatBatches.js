import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import ImportWhatsappChatBatchesAPI from '../../api/importWhatsappChatBatches';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
  },
};

export const getters = {
  getBatches(_state) {
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
      const response = await ImportWhatsappChatBatchesAPI.get();
      commit('setBatches', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    const response = await ImportWhatsappChatBatchesAPI.create(data);
    commit('addBatch', response.data);
    return response.data;
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setBatches: MutationHelpers.set,
  addBatch: MutationHelpers.create,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

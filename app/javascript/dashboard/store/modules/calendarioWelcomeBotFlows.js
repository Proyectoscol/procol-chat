import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioWelcomeBotFlowsAPI from '../../api/calendarioWelcomeBotFlows';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getFlows(_state) {
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
      const response = await CalendarioWelcomeBotFlowsAPI.get();
      commit('setFlows', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await CalendarioWelcomeBotFlowsAPI.create({
        welcome_bot_flow: data,
      });
      commit('addFlow', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await CalendarioWelcomeBotFlowsAPI.update(id, {
        welcome_bot_flow: data,
      });
      commit('editFlow', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('setUIFlags', { isDeleting: true });
    try {
      await CalendarioWelcomeBotFlowsAPI.delete(id);
      commit('removeFlow', id);
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setFlows: MutationHelpers.set,
  addFlow: MutationHelpers.create,
  editFlow: MutationHelpers.update,
  removeFlow: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

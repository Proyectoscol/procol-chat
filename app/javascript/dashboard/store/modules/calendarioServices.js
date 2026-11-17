import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioServicesAPI from '../../api/calendarioServices';

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
  getServices(_state) {
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
      const response = await CalendarioServicesAPI.get();
      commit('setServices', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await CalendarioServicesAPI.create({ service: data });
      commit('addService', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await CalendarioServicesAPI.update(id, {
        service: data,
      });
      commit('editService', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('setUIFlags', { isDeleting: true });
    try {
      await CalendarioServicesAPI.delete(id);
      commit('deleteService', id);
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setServices: MutationHelpers.set,
  addService: MutationHelpers.create,
  editService: MutationHelpers.update,
  deleteService: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

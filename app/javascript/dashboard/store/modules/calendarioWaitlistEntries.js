import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioWaitlistEntriesAPI from '../../api/calendarioWaitlistEntries';

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
  getWaitlistEntries(_state) {
    return _state.records;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }, { professionalId } = {}) => {
    commit('setUIFlags', { isFetching: true });
    try {
      const response = await CalendarioWaitlistEntriesAPI.get({
        professionalId,
      });
      commit('setWaitlistEntries', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await CalendarioWaitlistEntriesAPI.create({
        waitlist_entry: data,
      });
      commit('addWaitlistEntry', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await CalendarioWaitlistEntriesAPI.update(id, {
        waitlist_entry: data,
      });
      commit('editWaitlistEntry', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('setUIFlags', { isDeleting: true });
    try {
      await CalendarioWaitlistEntriesAPI.delete(id);
      commit('deleteWaitlistEntry', id);
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setWaitlistEntries: MutationHelpers.set,
  addWaitlistEntry: MutationHelpers.create,
  editWaitlistEntry: MutationHelpers.update,
  deleteWaitlistEntry: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

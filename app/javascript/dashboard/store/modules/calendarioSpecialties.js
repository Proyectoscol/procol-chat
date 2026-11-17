import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioSpecialtiesAPI from '../../api/calendarioSpecialties';

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
  getSpecialties(_state) {
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
      const response = await CalendarioSpecialtiesAPI.get();
      commit('setSpecialties', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await CalendarioSpecialtiesAPI.create({
        specialty: data,
      });
      commit('addSpecialty', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await CalendarioSpecialtiesAPI.update(id, {
        specialty: data,
      });
      commit('editSpecialty', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('setUIFlags', { isDeleting: true });
    try {
      await CalendarioSpecialtiesAPI.delete(id);
      commit('deleteSpecialty', id);
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setSpecialties: MutationHelpers.set,
  addSpecialty: MutationHelpers.create,
  editSpecialty: MutationHelpers.update,
  deleteSpecialty: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

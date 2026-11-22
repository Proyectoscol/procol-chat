import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioMessageTemplatesAPI from '../../api/calendarioMessageTemplates';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isActivating: false,
  },
};

export const getters = {
  getTemplates(_state) {
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
      const response = await CalendarioMessageTemplatesAPI.get();
      commit('setTemplates', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await CalendarioMessageTemplatesAPI.create({
        message_template: data,
      });
      commit('addTemplate', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await CalendarioMessageTemplatesAPI.update(id, {
        message_template: data,
      });
      commit('editTemplate', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('setUIFlags', { isDeleting: true });
    try {
      await CalendarioMessageTemplatesAPI.delete(id);
      commit('removeTemplate', id);
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },

  // Activar una version tambien vuelve "draft" a su(s) hermana(s) del mismo
  // key en el backend (ver Calendario::MessageTemplate#activate!) -- se
  // vuelve a pedir la lista completa en vez de parchar un solo registro
  // para que esos cambios de estado tambien se reflejen en memoria.
  activate: async ({ commit, dispatch }, id) => {
    commit('setUIFlags', { isActivating: true });
    try {
      await CalendarioMessageTemplatesAPI.activate(id);
      await dispatch('get');
    } finally {
      commit('setUIFlags', { isActivating: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setTemplates: MutationHelpers.set,
  addTemplate: MutationHelpers.create,
  editTemplate: MutationHelpers.update,
  removeTemplate: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

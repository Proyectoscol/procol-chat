import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioAppointmentEventTriggersAPI from '../../api/calendarioAppointmentEventTriggers';

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
  getTriggers(_state) {
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
      const response = await CalendarioAppointmentEventTriggersAPI.get();
      commit('setTriggers', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await CalendarioAppointmentEventTriggersAPI.create({
        appointment_event_trigger: data,
      });
      commit('addTrigger', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await CalendarioAppointmentEventTriggersAPI.update(id, {
        appointment_event_trigger: data,
      });
      commit('editTrigger', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('setUIFlags', { isDeleting: true });
    try {
      await CalendarioAppointmentEventTriggersAPI.delete(id);
      commit('removeTrigger', id);
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setTriggers: MutationHelpers.set,
  addTrigger: MutationHelpers.create,
  editTrigger: MutationHelpers.update,
  removeTrigger: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

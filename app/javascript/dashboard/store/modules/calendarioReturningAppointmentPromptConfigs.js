import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioReturningAppointmentPromptConfigsAPI from '../../api/calendarioReturningAppointmentPromptConfigs';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
  },
};

export const getters = {
  getConfigs(_state) {
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
      const response =
        await CalendarioReturningAppointmentPromptConfigsAPI.get();
      commit('setConfigs', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response =
        await CalendarioReturningAppointmentPromptConfigsAPI.create({
          returning_appointment_prompt_config: data,
        });
      commit('addConfig', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response =
        await CalendarioReturningAppointmentPromptConfigsAPI.update(id, {
          returning_appointment_prompt_config: data,
        });
      commit('editConfig', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setConfigs: MutationHelpers.set,
  addConfig: MutationHelpers.create,
  editConfig: MutationHelpers.update,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioOpenDaysAPI from '../../api/calendarioOpenDays';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isDeleting: false,
  },
};

export const getters = {
  getOpenDays(_state) {
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
      const response = await CalendarioOpenDaysAPI.get({ professionalId });
      commit('setOpenDays', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  // Un duplicado (mismo profesional+fecha+franja) tira 409 -- quien llama
  // atrapa el error y decide si reintenta con force:true (ver patron de
  // AppointmentBookingService).
  create: async ({ commit }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await CalendarioOpenDaysAPI.create({
        open_day: data,
      });
      commit('addOpenDay', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('setUIFlags', { isDeleting: true });
    try {
      await CalendarioOpenDaysAPI.delete(id);
      commit('deleteOpenDay', id);
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setOpenDays: MutationHelpers.set,
  addOpenDay: MutationHelpers.create,
  deleteOpenDay: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

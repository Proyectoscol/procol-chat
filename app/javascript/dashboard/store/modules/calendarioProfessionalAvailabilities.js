import CalendarioProfessionalAvailabilitiesAPI from '../../api/calendarioProfessionalAvailabilities';

export const state = {
  records: [],
  professionalId: null,
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isDeleting: false,
  },
};

export const getters = {
  getAvailabilities(_state) {
    return _state.records;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }, professionalId) => {
    commit('setUIFlags', { isFetching: true });
    try {
      const response =
        await CalendarioProfessionalAvailabilitiesAPI.get(professionalId);
      commit('setAvailabilities', { professionalId, records: response.data });
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit }, { professionalId, ...data }) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await CalendarioProfessionalAvailabilitiesAPI.create(
        professionalId,
        {
          availability: data,
        }
      );
      commit('addAvailability', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  delete: async ({ commit }, { professionalId, id }) => {
    commit('setUIFlags', { isDeleting: true });
    try {
      await CalendarioProfessionalAvailabilitiesAPI.delete(professionalId, id);
      commit('removeAvailability', id);
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setAvailabilities(_state, { professionalId, records }) {
    _state.professionalId = professionalId;
    _state.records = records;
  },
  addAvailability(_state, record) {
    _state.records.push(record);
  },
  removeAvailability(_state, id) {
    _state.records = _state.records.filter(record => record.id !== id);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

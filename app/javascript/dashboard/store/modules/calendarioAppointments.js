import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import CalendarioAppointmentsAPI from '../../api/calendarioAppointments';

export const state = {
  records: [],
  agendaRecords: [],
  contactRecords: [],
  // Lista aparte para el drill-down de auditoria (CalendarioStatsPage, modo
  // "creadas") -- no se mezcla con `records` para no pisar la lista que usa
  // la Vista calendario/Agendas al cambiar de pestana.
  createdRangeRecords: [],
  uiFlags: {
    isFetching: false,
    isFetchingAgenda: false,
    isFetchingByContact: false,
    isFetchingByCreatedRange: false,
    isCreating: false,
    isUpdating: false,
  },
};

export const getters = {
  getAppointments(_state) {
    return _state.records;
  },
  getAgendaAppointments(_state) {
    return _state.agendaRecords;
  },
  getContactAppointments(_state) {
    return _state.contactRecords;
  },
  getCreatedRangeAppointments(_state) {
    return _state.createdRangeRecords;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  getRange: async ({ commit }, range) => {
    commit('setUIFlags', { isFetching: true });
    try {
      const response = await CalendarioAppointmentsAPI.getRange(range);
      commit('setAppointments', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  // Agrega un lote de citas de un rango MAS ANTIGUO al ya cargado (ver
  // "cargar mas" en CalendarioSchedulesPage) en vez de reemplazar `records`
  // -- lo que ya esta cargado (lo reciente, que es lo que se ve al entrar)
  // no se debe perder ni re-pedir cada vez que se extiende hacia el pasado.
  extendRange: async ({ commit }, range) => {
    commit('setUIFlags', { isFetching: true });
    try {
      const response = await CalendarioAppointmentsAPI.getRange(range);
      commit('mergeAppointments', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  getAgenda: async ({ commit }) => {
    commit('setUIFlags', { isFetchingAgenda: true });
    try {
      const response = await CalendarioAppointmentsAPI.getAgenda();
      commit('setAgendaAppointments', response.data);
    } finally {
      commit('setUIFlags', { isFetchingAgenda: false });
    }
  },

  getByContact: async ({ commit }, contactId) => {
    commit('setUIFlags', { isFetchingByContact: true });
    try {
      const response = await CalendarioAppointmentsAPI.getByContact(contactId);
      commit('setContactAppointments', response.data);
    } finally {
      commit('setUIFlags', { isFetchingByContact: false });
    }
  },

  getByCreatedRange: async ({ commit }, range) => {
    commit('setUIFlags', { isFetchingByCreatedRange: true });
    try {
      const response = await CalendarioAppointmentsAPI.getByCreatedRange(range);
      commit('setCreatedRangeAppointments', response.data);
    } finally {
      commit('setUIFlags', { isFetchingByCreatedRange: false });
    }
  },

  create: async ({ commit }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await CalendarioAppointmentsAPI.create({
        appointment: data,
      });
      commit('addAppointment', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await CalendarioAppointmentsAPI.update(id, {
        appointment: data,
      });
      commit('editAppointment', response.data);
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
  setAppointments: MutationHelpers.set,
  mergeAppointments(_state, data) {
    const existingIds = new Set(_state.records.map(record => record.id));
    const newOnes = data.filter(record => !existingIds.has(record.id));
    _state.records = [..._state.records, ...newOnes];
  },
  addAppointment: MutationHelpers.create,
  editAppointment(_state, data) {
    MutationHelpers.update(_state, data);
    _state.agendaRecords = _state.agendaRecords.map(record =>
      record.id === data.id ? data : record
    );
    _state.contactRecords = _state.contactRecords.map(record =>
      record.id === data.id ? data : record
    );
  },
  setAgendaAppointments(_state, data) {
    _state.agendaRecords = data;
  },
  setContactAppointments(_state, data) {
    _state.contactRecords = data;
  },
  setCreatedRangeAppointments(_state, data) {
    _state.createdRangeRecords = data;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

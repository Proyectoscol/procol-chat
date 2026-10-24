import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import AuditoriaCategoriesAPI from '../../api/auditoriaCategories';

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
  getCategories(_state) {
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
      const response = await AuditoriaCategoriesAPI.get();
      commit('setCategories', response.data);
    } finally {
      commit('setUIFlags', { isFetching: false });
    }
  },

  create: async ({ commit, dispatch }, data) => {
    commit('setUIFlags', { isCreating: true });
    try {
      const response = await AuditoriaCategoriesAPI.create({ category: data });
      commit('addCategory', response.data);
      // Si esta es la primera subcategoria de su padre, el padre pasa a ser
      // agrupacion (has_subcategories) -- recargar para que la tabla lo
      // refleje sin esperar a un F5 (ver Auditoria::CategoriesController#create).
      if (data.parent_id) await dispatch('get');
      return response.data;
    } finally {
      commit('setUIFlags', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit('setUIFlags', { isUpdating: true });
    try {
      const response = await AuditoriaCategoriesAPI.update(id, {
        category: data,
      });
      commit('editCategory', response.data);
      return response.data;
    } finally {
      commit('setUIFlags', { isUpdating: false });
    }
  },

  delete: async ({ commit, dispatch, state: moduleState }, id) => {
    commit('setUIFlags', { isDeleting: true });
    try {
      const { parent_id: parentId } =
        moduleState.records.find(c => c.id === id) || {};
      await AuditoriaCategoriesAPI.delete(id);
      commit('removeCategory', id);
      // Simetrico al create: si esta era la ultima subcategoria de su padre,
      // el padre vuelve a ser hoja (ver Auditoria::CategoriesController#destroy).
      if (parentId) await dispatch('get');
    } finally {
      commit('setUIFlags', { isDeleting: false });
    }
  },
};

export const mutations = {
  setUIFlags(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  setCategories: MutationHelpers.set,
  addCategory: MutationHelpers.create,
  editCategory: MutationHelpers.update,
  removeCategory: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

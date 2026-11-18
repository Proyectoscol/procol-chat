import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import AgentAvailabilitySchedulesAPI from '../../api/agentAvailabilitySchedules';
import { throwErrorMessage } from '../utils/api';
import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';

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
  getAgentAvailabilitySchedules(_state) {
    return _state.records;
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
};

export const actions = {
  get: async function get({ commit }) {
    commit(types.SET_AGENT_AVAILABILITY_SCHEDULES_UI_FLAG, {
      isFetching: true,
    });
    try {
      const response = await AgentAvailabilitySchedulesAPI.get();
      commit(
        types.SET_AGENT_AVAILABILITY_SCHEDULES,
        camelcaseKeys(response.data, { deep: true })
      );
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_AGENT_AVAILABILITY_SCHEDULES_UI_FLAG, {
        isFetching: false,
      });
    }
  },

  create: async function create({ commit }, scheduleObj) {
    commit(types.SET_AGENT_AVAILABILITY_SCHEDULES_UI_FLAG, {
      isCreating: true,
    });
    try {
      const response = await AgentAvailabilitySchedulesAPI.create(
        snakecaseKeys(scheduleObj)
      );
      commit(
        types.ADD_AGENT_AVAILABILITY_SCHEDULE,
        camelcaseKeys(response.data, { deep: true })
      );
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit(types.SET_AGENT_AVAILABILITY_SCHEDULES_UI_FLAG, {
        isCreating: false,
      });
    }
  },

  update: async function update({ commit }, { id, ...scheduleParams }) {
    commit(types.SET_AGENT_AVAILABILITY_SCHEDULES_UI_FLAG, {
      isUpdating: true,
    });
    try {
      const response = await AgentAvailabilitySchedulesAPI.update(
        id,
        snakecaseKeys(scheduleParams)
      );
      commit(
        types.EDIT_AGENT_AVAILABILITY_SCHEDULE,
        camelcaseKeys(response.data, { deep: true })
      );
      return response.data;
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit(types.SET_AGENT_AVAILABILITY_SCHEDULES_UI_FLAG, {
        isUpdating: false,
      });
    }
  },

  delete: async function deleteSchedule({ commit }, scheduleId) {
    commit(types.SET_AGENT_AVAILABILITY_SCHEDULES_UI_FLAG, {
      isDeleting: true,
    });
    try {
      await AgentAvailabilitySchedulesAPI.delete(scheduleId);
      commit(types.DELETE_AGENT_AVAILABILITY_SCHEDULE, scheduleId);
    } catch (error) {
      throwErrorMessage(error);
      throw error;
    } finally {
      commit(types.SET_AGENT_AVAILABILITY_SCHEDULES_UI_FLAG, {
        isDeleting: false,
      });
    }
  },
};

export const mutations = {
  [types.SET_AGENT_AVAILABILITY_SCHEDULES_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.SET_AGENT_AVAILABILITY_SCHEDULES]: MutationHelpers.set,
  [types.ADD_AGENT_AVAILABILITY_SCHEDULE]: MutationHelpers.create,
  [types.EDIT_AGENT_AVAILABILITY_SCHEDULE]: MutationHelpers.updateAttributes,
  [types.DELETE_AGENT_AVAILABILITY_SCHEDULE]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};

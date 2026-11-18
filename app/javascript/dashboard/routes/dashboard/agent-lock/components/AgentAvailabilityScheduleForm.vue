<script setup>
import { reactive, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, requiredIf } from '@vuelidate/validators';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  mode: {
    type: String,
    required: true,
    validator: value => ['create', 'edit'].includes(value),
  },
  schedule: {
    type: Object,
    default: () => ({}),
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

store.dispatch('agents/get');
const agentList = computed(() => getters['agents/getAgents'].value);
const agentOptions = computed(() =>
  agentList.value.map(agent => ({
    value: agent.id,
    label: `${agent.name} (${agent.email})`,
  }))
);

// Matches Ruby's Date#wday (0 = Sunday ... 6 = Saturday) so the value saved
// here lines up directly with what AgentAvailabilitySchedule#applies_on? checks.
const WEEKDAYS = [
  { value: 1, label: 'MON' },
  { value: 2, label: 'TUE' },
  { value: 3, label: 'WED' },
  { value: 4, label: 'THU' },
  { value: 5, label: 'FRI' },
  { value: 6, label: 'SAT' },
  { value: 0, label: 'SUN' },
];

const initialState = {
  userId: '',
  startsOn: '',
  endsOn: '',
  startTime: '',
  endTime: '',
  weekdays: [1, 2, 3, 4, 5],
  active: true,
};

const state = reactive({ ...initialState });

const endsOnNotBeforeStartsOn = value =>
  !state.startsOn || !value || value >= state.startsOn;
const endTimeAfterStartTime = value =>
  !state.startTime || !value || value > state.startTime;

const validationRules = {
  userId: { required },
  startsOn: { required },
  endsOn: { required, endsOnNotBeforeStartsOn },
  startTime: { required },
  endTime: { required, endTimeAfterStartTime },
  weekdays: { required: requiredIf(() => state.weekdays.length === 0) },
};

const v$ = useVuelidate(validationRules, state);

const getErrorMessage = (field, errorKey) =>
  v$.value[field].$error ? t(`AGENT_LOCK.SCHEDULE.FORM.${errorKey}.ERROR`) : '';

const formErrors = computed(() => ({
  userId: getErrorMessage('userId', 'AGENT'),
  startsOn: getErrorMessage('startsOn', 'STARTS_ON'),
  endsOn: getErrorMessage('endsOn', 'ENDS_ON'),
  startTime: getErrorMessage('startTime', 'START_TIME'),
  endTime: getErrorMessage('endTime', 'END_TIME'),
}));

const toggleWeekday = day => {
  state.weekdays = state.weekdays.includes(day)
    ? state.weekdays.filter(value => value !== day)
    : [...state.weekdays, day];
};

const handleCancel = () => emit('cancel');

const prepareScheduleDetails = () => ({
  user_id: state.userId,
  starts_on: state.startsOn,
  ends_on: state.endsOn,
  start_time: state.startTime,
  end_time: state.endTime,
  weekdays: state.weekdays,
  active: state.active,
});

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) return;

  emit('submit', prepareScheduleDetails());
};

const updateStateFromSchedule = schedule => {
  if (!schedule) return;

  Object.assign(state, {
    userId: schedule.userId ?? '',
    startsOn: schedule.startsOn ?? '',
    endsOn: schedule.endsOn ?? '',
    startTime: schedule.startTime ?? '',
    endTime: schedule.endTime ?? '',
    weekdays: schedule.weekdays ?? [1, 2, 3, 4, 5],
    active: schedule.active ?? true,
  });
};

watch(
  () => props.schedule,
  newSchedule => {
    if (props.mode === 'edit' && newSchedule) {
      updateStateFromSchedule(newSchedule);
    }
  },
  { immediate: true }
);
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <div class="flex flex-col gap-1">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('AGENT_LOCK.SCHEDULE.FORM.AGENT.LABEL') }}
      </label>
      <ComboBox
        v-model="state.userId"
        :options="agentOptions"
        :placeholder="t('AGENT_LOCK.SCHEDULE.FORM.AGENT.PLACEHOLDER')"
        :search-placeholder="t('AGENT_LOCK.SEARCH_PLACEHOLDER')"
        :has-error="!!formErrors.userId"
        :message="formErrors.userId"
      />
    </div>

    <div class="grid grid-cols-2 gap-4">
      <Input
        v-model="state.startsOn"
        type="date"
        :label="t('AGENT_LOCK.SCHEDULE.FORM.STARTS_ON.LABEL')"
        :message="formErrors.startsOn"
        :message-type="formErrors.startsOn ? 'error' : 'info'"
      />
      <Input
        v-model="state.endsOn"
        type="date"
        :label="t('AGENT_LOCK.SCHEDULE.FORM.ENDS_ON.LABEL')"
        :message="formErrors.endsOn"
        :message-type="formErrors.endsOn ? 'error' : 'info'"
      />
    </div>

    <div class="grid grid-cols-2 gap-4">
      <Input
        v-model="state.startTime"
        type="time"
        :label="t('AGENT_LOCK.SCHEDULE.FORM.START_TIME.LABEL')"
        :message="formErrors.startTime"
        :message-type="formErrors.startTime ? 'error' : 'info'"
      />
      <Input
        v-model="state.endTime"
        type="time"
        :label="t('AGENT_LOCK.SCHEDULE.FORM.END_TIME.LABEL')"
        :message="formErrors.endTime"
        :message-type="formErrors.endTime ? 'error' : 'info'"
      />
    </div>

    <fieldset class="flex flex-col gap-2.5">
      <legend class="mb-2 text-sm font-medium text-n-slate-12">
        {{ t('AGENT_LOCK.SCHEDULE.FORM.WEEKDAYS.LABEL') }}
      </legend>
      <div class="flex flex-wrap gap-4">
        <label
          v-for="day in WEEKDAYS"
          :key="day.value"
          class="flex items-center gap-1.5"
        >
          <Checkbox
            :model-value="state.weekdays.includes(day.value)"
            @change="() => toggleWeekday(day.value)"
          />
          <span class="text-sm text-n-slate-11">
            {{ t(`AGENT_LOCK.SCHEDULE.FORM.WEEKDAYS.${day.label}`) }}
          </span>
        </label>
      </div>
    </fieldset>

    <div class="flex items-center justify-between">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('AGENT_LOCK.SCHEDULE.FORM.ACTIVE.LABEL') }}
      </span>
      <Switch v-model="state.active" />
    </div>

    <div class="flex items-center justify-between w-full gap-3">
      <Button
        type="button"
        variant="faded"
        color="slate"
        :label="t('AGENT_LOCK.SCHEDULE.FORM.CANCEL')"
        class="w-full"
        @click="handleCancel"
      />
      <Button
        type="submit"
        :label="t(`AGENT_LOCK.SCHEDULE.FORM.${mode.toUpperCase()}`)"
        class="w-full"
        :is-loading="isLoading"
        :disabled="isLoading"
      />
    </div>
  </form>
</template>

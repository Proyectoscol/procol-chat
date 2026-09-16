<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AgentAvailabilityScheduleDialog from './AgentAvailabilityScheduleDialog.vue';

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const WEEKDAY_LABELS = {
  0: 'SUN',
  1: 'MON',
  2: 'TUE',
  3: 'WED',
  4: 'THU',
  5: 'FRI',
  6: 'SAT',
};

const schedules = computed(
  () =>
    getters['agentAvailabilitySchedules/getAgentAvailabilitySchedules'].value
);
const uiFlags = computed(
  () => getters['agentAvailabilitySchedules/getUIFlags'].value
);

const scheduleDialog = ref(null);
const deleteDialog = ref(null);
const dialogType = ref('create');
const selectedSchedule = ref({});
const scheduleToDelete = ref(null);

const weekdaySummary = schedule =>
  schedule.weekdays
    .slice()
    .sort((a, b) => a - b)
    .map(day => t(`AGENT_LOCK.SCHEDULE.FORM.WEEKDAYS.${WEEKDAY_LABELS[day]}`))
    .join(', ');

const openCreateDialog = () => {
  dialogType.value = 'create';
  selectedSchedule.value = {};
  scheduleDialog.value.dialogRef.open();
};

const openEditDialog = schedule => {
  dialogType.value = 'edit';
  selectedSchedule.value = schedule;
  scheduleDialog.value.dialogRef.open();
};

const confirmDelete = schedule => {
  scheduleToDelete.value = schedule;
  deleteDialog.value.open();
};

const handleDelete = async () => {
  try {
    await store.dispatch(
      'agentAvailabilitySchedules/delete',
      scheduleToDelete.value.id
    );
    useAlert(t('AGENT_LOCK.SCHEDULE.DELETE.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(error?.message || t('AGENT_LOCK.SCHEDULE.DELETE.ERROR_MESSAGE'));
  } finally {
    deleteDialog.value.close();
  }
};

onMounted(() => {
  store.dispatch('agentAvailabilitySchedules/get');
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex justify-end">
      <Button
        :label="t('AGENT_LOCK.SCHEDULE.CREATE.TITLE')"
        icon="i-lucide-plus"
        @click="openCreateDialog"
      />
    </div>

    <span
      v-if="uiFlags.isFetching"
      class="flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
    >
      {{ t('AGENT_LOCK.LOADING') }}
    </span>
    <span
      v-else-if="!schedules.length"
      class="flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
    >
      {{ t('AGENT_LOCK.SCHEDULE.EMPTY_STATE') }}
    </span>
    <div v-else class="overflow-x-auto border rounded-xl border-n-weak">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-n-weak bg-n-solid-1">
            <th class="px-4 py-2 text-left text-n-slate-11">
              {{ t('AGENT_LOCK.SCHEDULE.LIST.AGENT') }}
            </th>
            <th class="px-4 py-2 text-left text-n-slate-11">
              {{ t('AGENT_LOCK.SCHEDULE.LIST.DATE_RANGE') }}
            </th>
            <th class="px-4 py-2 text-left text-n-slate-11">
              {{ t('AGENT_LOCK.SCHEDULE.LIST.TIME_RANGE') }}
            </th>
            <th class="px-4 py-2 text-left text-n-slate-11">
              {{ t('AGENT_LOCK.SCHEDULE.LIST.WEEKDAYS') }}
            </th>
            <th class="px-4 py-2 text-left text-n-slate-11">
              {{ t('AGENT_LOCK.SCHEDULE.LIST.STATUS') }}
            </th>
            <th class="px-4 py-2" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="schedule in schedules"
            :key="schedule.id"
            class="border-b border-n-weak last:border-0"
          >
            <td class="px-4 py-2">
              <div class="flex flex-col">
                <span class="font-medium text-n-slate-12">
                  {{ schedule.agentName }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{ schedule.agentEmail }}
                </span>
              </div>
            </td>
            <td class="px-4 py-2 text-n-slate-11">
              {{ schedule.startsOn }} — {{ schedule.endsOn }}
            </td>
            <td class="px-4 py-2 text-n-slate-11">
              {{ schedule.startTime }} — {{ schedule.endTime }}
            </td>
            <td class="px-4 py-2 text-n-slate-11">
              {{ weekdaySummary(schedule) }}
            </td>
            <td class="px-4 py-2">
              <span
                v-if="!schedule.active"
                class="px-2 py-0.5 rounded-md text-xs font-medium bg-n-alpha-2 text-n-slate-11"
              >
                {{ t('AGENT_LOCK.SCHEDULE.LIST.INACTIVE') }}
              </span>
              <span
                v-else-if="schedule.currentlyLocked"
                class="px-2 py-0.5 rounded-md text-xs font-medium bg-n-ruby-3 text-n-ruby-11"
              >
                {{ t('AGENT_LOCK.SCHEDULE.LIST.LOCKED_NOW') }}
              </span>
              <span
                v-else
                class="px-2 py-0.5 rounded-md text-xs font-medium bg-n-teal-3 text-n-teal-11"
              >
                {{ t('AGENT_LOCK.SCHEDULE.LIST.ACTIVE') }}
              </span>
            </td>
            <td class="px-4 py-2">
              <div class="flex items-center justify-end gap-1">
                <Button
                  icon="i-lucide-pencil"
                  variant="ghost"
                  color="slate"
                  size="sm"
                  @click="openEditDialog(schedule)"
                />
                <Button
                  icon="i-lucide-trash"
                  variant="ghost"
                  color="ruby"
                  size="sm"
                  @click="confirmDelete(schedule)"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <AgentAvailabilityScheduleDialog
      ref="scheduleDialog"
      :type="dialogType"
      :selected-schedule="selectedSchedule"
    />

    <Dialog
      ref="deleteDialog"
      type="alert"
      :title="t('AGENT_LOCK.SCHEDULE.DELETE.TITLE')"
      :description="t('AGENT_LOCK.SCHEDULE.DELETE.DESCRIPTION')"
      :confirm-button-label="t('AGENT_LOCK.SCHEDULE.DELETE.CONFIRM')"
      @confirm="handleDelete"
    />
  </div>
</template>

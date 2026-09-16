<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import AgentAvailabilityScheduleForm from './AgentAvailabilityScheduleForm.vue';

const props = defineProps({
  selectedSchedule: {
    type: Object,
    default: () => ({}),
  },
  type: {
    type: String,
    default: 'create',
    validator: value => ['create', 'edit'].includes(value),
  },
});

const emit = defineEmits(['close', 'saved']);
const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const isSaving = ref(false);

const i18nKey = computed(
  () => `AGENT_LOCK.SCHEDULE.${props.type.toUpperCase()}`
);

const handleSubmit = async scheduleDetails => {
  isSaving.value = true;
  try {
    if (props.type === 'edit') {
      await store.dispatch('agentAvailabilitySchedules/update', {
        id: props.selectedSchedule.id,
        ...scheduleDetails,
      });
    } else {
      await store.dispatch(
        'agentAvailabilitySchedules/create',
        scheduleDetails
      );
    }
    useAlert(t(`${i18nKey.value}.SUCCESS_MESSAGE`));
    emit('saved');
    dialogRef.value.close();
  } catch (error) {
    useAlert(error?.message || t(`${i18nKey.value}.ERROR_MESSAGE`));
  } finally {
    isSaving.value = false;
  }
};

const handleClose = () => emit('close');
const handleCancel = () => dialogRef.value.close();

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t(`${i18nKey}.TITLE`)"
    :description="t('AGENT_LOCK.SCHEDULE.FORM_DESCRIPTION')"
    :show-cancel-button="false"
    :show-confirm-button="false"
    overflow-y-auto
    @close="handleClose"
  >
    <AgentAvailabilityScheduleForm
      :mode="type"
      :schedule="selectedSchedule"
      :is-loading="isSaving"
      @submit="handleSubmit"
      @cancel="handleCancel"
    />
    <template #footer />
  </Dialog>
</template>

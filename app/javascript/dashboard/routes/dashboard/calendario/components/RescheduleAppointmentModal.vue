<script setup>
import { useI18n } from 'vue-i18n';
import RescheduleAppointmentContent from './RescheduleAppointmentContent.vue';

defineProps({
  appointment: { type: Object, required: true },
});
defineEmits(['close']);

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="t('CALENDARIO.APPOINTMENTS.RESCHEDULE.TITLE')"
    />
    <div class="px-4 pb-4">
      <RescheduleAppointmentContent
        :appointment="appointment"
        @close="$emit('close')"
      />
    </div>
  </div>
</template>

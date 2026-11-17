<script setup>
import { useI18n } from 'vue-i18n';
import AppointmentDetailContent from './AppointmentDetailContent.vue';

defineProps({
  appointmentId: { type: [Number, String], required: true },
});
defineEmits(['close', 'reschedule', 'cancel', 'changed']);

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="t('CALENDARIO.APPOINTMENTS.DETAIL.TITLE')"
    />
    <div class="px-4 pb-4">
      <AppointmentDetailContent
        :appointment-id="appointmentId"
        @close="$emit('close')"
        @reschedule="$emit('reschedule', $event)"
        @cancel="$emit('cancel', $event)"
        @changed="$emit('changed')"
      />
    </div>
  </div>
</template>

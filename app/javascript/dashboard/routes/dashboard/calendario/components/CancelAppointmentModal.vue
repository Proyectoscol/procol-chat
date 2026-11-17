<script setup>
import { useI18n } from 'vue-i18n';
import CancelAppointmentContent from './CancelAppointmentContent.vue';

defineProps({
  appointment: { type: Object, required: true },
});
defineEmits(['close', 'cancelled']);

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.TITLE')"
    />
    <div class="px-4 pb-4">
      <CancelAppointmentContent
        :appointment="appointment"
        @close="$emit('close')"
        @cancelled="$emit('cancelled', $event)"
      />
    </div>
  </div>
</template>

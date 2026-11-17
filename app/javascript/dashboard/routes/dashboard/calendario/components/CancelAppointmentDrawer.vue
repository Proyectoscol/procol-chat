<script setup>
import { useI18n } from 'vue-i18n';
import CancelAppointmentContent from './CancelAppointmentContent.vue';

defineProps({
  show: { type: Boolean, default: false },
  appointment: { type: Object, default: null },
});
defineEmits(['close', 'cancelled']);

const { t } = useI18n();
</script>

<template>
  <!-- Mismo criterio que AppointmentDetailDrawer/RescheduleAppointmentDrawer:
  sin backdrop, flotando sobre el borde derecho, para que el chat siga
  visible mientras se escribe el motivo de la cancelacion. -->
  <div
    class="fixed top-0 bottom-0 right-0 z-50 flex flex-col w-full sm:w-[420px] bg-n-solid-1 border-l border-n-weak shadow-2xl transition-transform duration-200 ease-in-out"
    :class="show ? 'translate-x-0' : 'translate-x-full pointer-events-none'"
  >
    <div
      class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
    >
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('CALENDARIO.APPOINTMENTS.CANCEL_APPOINTMENT.TITLE') }}
      </h3>
      <button
        type="button"
        class="i-lucide-x size-5 text-n-slate-10 hover:text-n-slate-12"
        @click="$emit('close')"
      />
    </div>
    <div class="flex-1 overflow-y-auto p-4">
      <CancelAppointmentContent
        v-if="appointment"
        :key="appointment.id"
        :appointment="appointment"
        @close="$emit('close')"
        @cancelled="$emit('cancelled', $event)"
      />
    </div>
  </div>
</template>

<script setup>
import { useI18n } from 'vue-i18n';
import AppointmentFormContent from './AppointmentFormContent.vue';

defineProps({
  show: { type: Boolean, default: false },
  presetContact: { type: Object, default: null },
  presetConversationId: { type: [Number, String], default: null },
  presetStartsAt: { type: Date, default: null },
});
defineEmits(['close', 'created']);

const { t } = useI18n();
</script>

<template>
  <!-- Mismo criterio que los demas drawers de Calendario: sin backdrop, para
  que el chat siga visible mientras se arma la cita (ver feedback del
  2026-10-30). -->
  <div
    class="fixed top-0 bottom-0 right-0 z-30 flex flex-col w-full sm:w-[420px] bg-n-solid-1 border-l border-n-weak shadow-2xl transition-transform duration-200 ease-in-out"
    :class="show ? 'translate-x-0' : 'translate-x-full pointer-events-none'"
  >
    <div
      class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
    >
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.CREATE_TITLE') }}
      </h3>
      <button
        type="button"
        class="i-lucide-x size-5 text-n-slate-10 hover:text-n-slate-12"
        @click="$emit('close')"
      />
    </div>
    <div class="flex-1 overflow-y-auto p-4">
      <AppointmentFormContent
        v-if="show"
        :preset-contact="presetContact"
        :preset-conversation-id="presetConversationId"
        :preset-starts-at="presetStartsAt"
        @close="$emit('close')"
        @created="$emit('created', $event)"
      />
    </div>
  </div>
</template>

<script setup>
import { useI18n } from 'vue-i18n';
import AppointmentDetailContent from './AppointmentDetailContent.vue';

defineProps({
  show: { type: Boolean, default: false },
  appointmentId: { type: [Number, String], default: null },
});
defineEmits(['close', 'reschedule', 'cancel', 'changed']);

const { t } = useI18n();
</script>

<template>
  <!--
    A proposito SIN backdrop y SIN cubrir el chat: el asistente tiene que
    poder seguir seleccionando/copiando texto de la conversacion (correo,
    telefono) mientras ve el detalle de la cita -- un modal centrado con
    overlay se lo impide (ver feedback del 2026-10-30). Por eso esto flota
    sobre el borde derecho en vez de tapar la conversacion, y se mantiene
    montado (solo trasladado fuera de pantalla) para poder animar la entrada.
  -->
  <div
    class="fixed top-0 bottom-0 right-0 z-50 flex flex-col w-full sm:w-[420px] bg-n-solid-1 border-l border-n-weak shadow-2xl transition-transform duration-200 ease-in-out"
    :class="show ? 'translate-x-0' : 'translate-x-full pointer-events-none'"
  >
    <div
      class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
    >
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('CALENDARIO.APPOINTMENTS.DETAIL.TITLE') }}
      </h3>
      <button
        type="button"
        class="i-lucide-x size-5 text-n-slate-10 hover:text-n-slate-12"
        @click="$emit('close')"
      />
    </div>
    <div class="flex-1 overflow-y-auto p-4">
      <AppointmentDetailContent
        v-if="appointmentId"
        :key="appointmentId"
        :appointment-id="appointmentId"
        :show-open-conversation="false"
        @close="$emit('close')"
        @reschedule="$emit('reschedule', $event)"
        @cancel="$emit('cancel', $event)"
        @changed="$emit('changed')"
      />
    </div>
  </div>
</template>

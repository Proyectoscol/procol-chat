<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AppointmentDetailDrawer from './AppointmentDetailDrawer.vue';
import RescheduleAppointmentDrawer from './RescheduleAppointmentDrawer.vue';
import CancelAppointmentDrawer from './CancelAppointmentDrawer.vue';
import { formatInstantDateEs } from '../helpers/calendarioDateTime';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
});

const store = useStore();

const appointments = useMapGetter(
  'calendarioAppointments/getContactAppointments'
);

const showDetailDrawer = ref(false);
const selectedAppointmentId = ref(null);
const showRescheduleDrawer = ref(false);
const reschedulingAppointment = ref(null);
const showCancelDrawer = ref(false);
const cancellingAppointment = ref(null);

// Activas primero (ordenadas por fecha, la mas proxima primero), luego las
// terminadas (atendida/no asistio/cancelada) al final, bien apagadas -- el
// asistente escanea esta barra de un vistazo, lo que importa es "que viene"
// no "que ya paso".
const sortedAppointments = computed(() => {
  const isTerminal = status =>
    ['attended', 'no_show', 'cancelled'].includes(status);
  return [...appointments.value].sort((a, b) => {
    const aTerminal = isTerminal(a.status);
    const bTerminal = isTerminal(b.status);
    if (aTerminal !== bTerminal) return aTerminal ? 1 : -1;
    return new Date(a.starts_at) - new Date(b.starts_at);
  });
});

const isPast = appointment => new Date(appointment.starts_at) < new Date();

const pillClass = appointment => {
  const faded =
    isPast(appointment) ||
    ['attended', 'no_show', 'cancelled'].includes(appointment.status);
  return faded
    ? 'bg-n-alpha-1 text-n-slate-10'
    : 'bg-n-blue-3 text-n-blue-text font-medium';
};

const formatPillDate = value =>
  formatInstantDateEs(value, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });

const openDetail = appointment => {
  selectedAppointmentId.value = appointment.id;
  showDetailDrawer.value = true;
};
const closeDetail = () => {
  showDetailDrawer.value = false;
};

const openReschedule = appointment => {
  reschedulingAppointment.value = appointment;
  showRescheduleDrawer.value = true;
};
const closeReschedule = () => {
  showRescheduleDrawer.value = false;
};

const openCancel = appointment => {
  cancellingAppointment.value = appointment;
  showCancelDrawer.value = true;
};
const closeCancel = () => {
  showCancelDrawer.value = false;
};

const refresh = () => {
  if (props.contactId)
    store.dispatch('calendarioAppointments/getByContact', props.contactId);
};

watch(() => props.contactId, refresh);
onMounted(refresh);
</script>

<template>
  <div
    v-if="sortedAppointments.length"
    class="flex items-center gap-2 px-4 py-2 min-h-[44px] overflow-x-auto border-t border-n-weak bg-n-surface-1"
  >
    <span class="i-lucide-calendar-days size-5 shrink-0 text-n-slate-10" />
    <button
      v-for="appointment in sortedAppointments"
      :key="appointment.id"
      type="button"
      class="shrink-0 px-3 py-1.5 rounded-full text-sm whitespace-nowrap"
      :class="pillClass(appointment)"
      @click="openDetail(appointment)"
    >
      {{ appointment.service_name }} ·
      {{ formatPillDate(appointment.starts_at) }}
    </button>
  </div>

  <AppointmentDetailDrawer
    :show="showDetailDrawer"
    :appointment-id="selectedAppointmentId"
    @close="closeDetail"
    @reschedule="openReschedule"
    @cancel="openCancel"
    @changed="refresh"
  />

  <RescheduleAppointmentDrawer
    :show="showRescheduleDrawer"
    :appointment="reschedulingAppointment"
    @close="closeReschedule"
  />

  <CancelAppointmentDrawer
    :show="showCancelDrawer"
    :appointment="cancellingAppointment"
    @close="closeCancel"
    @cancelled="refresh"
  />
</template>

<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import AppointmentFormDrawer from 'dashboard/routes/dashboard/calendario/components/AppointmentFormDrawer.vue';
import RescheduleAppointmentDrawer from 'dashboard/routes/dashboard/calendario/components/RescheduleAppointmentDrawer.vue';
import CancelAppointmentDrawer from 'dashboard/routes/dashboard/calendario/components/CancelAppointmentDrawer.vue';
import {
  statusSelectOptions,
  statusRowBackgroundClass,
  RESCHEDULE_ACTION,
  rescheduleCountLabel,
  ACTION_BUTTON_VARIANT,
  ACTION_BUTTON_CLASS,
} from 'dashboard/routes/dashboard/calendario/helpers/appointmentStatusActions';
import { formatInstantDateTimeEs } from 'dashboard/routes/dashboard/calendario/helpers/calendarioDateTime';

const props = defineProps({
  contact: { type: Object, required: true },
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const store = useStore();

const appointments = useMapGetter(
  'calendarioAppointments/getContactAppointments'
);
const uiFlags = useMapGetter('calendarioAppointments/getUIFlags');
const isFetching = computed(() => uiFlags.value.isFetchingByContact);

const showFormDrawer = ref(false);
const showRescheduleDrawer = ref(false);
const reschedulingAppointment = ref(null);
const showCancelDrawer = ref(false);
const cancellingAppointment = ref(null);
const updatingId = ref(null);

const statusOptions = computed(() => statusSelectOptions(t));

const formatDateTime = value => formatInstantDateTimeEs(value);

const refresh = () =>
  store.dispatch('calendarioAppointments/getByContact', props.contact.id);

const openCreateDrawer = () => {
  showFormDrawer.value = true;
};
const closeFormDrawer = () => {
  showFormDrawer.value = false;
};

const openRescheduleDrawer = appointment => {
  reschedulingAppointment.value = appointment;
  showRescheduleDrawer.value = true;
};
const closeRescheduleDrawer = () => {
  showRescheduleDrawer.value = false;
};

const openCancelDrawer = appointment => {
  cancellingAppointment.value = appointment;
  showCancelDrawer.value = true;
};
const closeCancelDrawer = () => {
  showCancelDrawer.value = false;
};

const setStatus = async (appointment, status) => {
  if (status === 'cancelled') {
    openCancelDrawer(appointment);
    return;
  }
  updatingId.value = appointment.id;
  try {
    await store.dispatch('calendarioAppointments/update', {
      id: appointment.id,
      status,
    });
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CALENDARIO.APPOINTMENTS.UPDATE_ERROR')
    );
  } finally {
    updatingId.value = null;
  }
};

// ContactPanel.vue mantiene esta misma instancia del componente al cambiar
// de conversacion (el sidebar lo renderiza dentro de un Draggable con
// item-key="name", no por contacto) -- onMounted nunca vuelve a correr, asi
// que sin este watch la tarjeta se queda mostrando la cita del contacto
// anterior. Mismo patron que ContactPanel.vue#watch(contactId, ...).
watch(
  () => props.contact?.id,
  (newId, oldId) => {
    if (newId && newId !== oldId) refresh();
  },
  { immediate: true }
);
store.dispatch('calendarioServices/get');
store.dispatch('calendarioProfessionals/get');
</script>

<template>
  <div class="flex flex-col gap-3 px-4 pt-3 pb-4">
    <Button
      size="sm"
      class="w-full"
      :label="t('CALENDARIO.APPOINTMENTS.ADD_BUTTON')"
      @click="openCreateDrawer"
    />

    <div v-if="isFetching" class="flex items-center justify-center py-4">
      <Spinner />
    </div>
    <div v-else-if="appointments.length" class="flex flex-col gap-2">
      <div
        v-for="appointment in appointments"
        :key="appointment.id"
        class="flex flex-col gap-1 rounded-xl border border-n-weak p-2"
        :class="statusRowBackgroundClass(appointment.status)"
      >
        <span class="text-sm font-medium text-n-slate-12">{{
          appointment.service_name
        }}</span>
        <span class="text-xs text-n-slate-11">{{
          formatDateTime(appointment.starts_at)
        }}</span>
        <span class="text-xs text-n-slate-10">{{
          appointment.professional_name
        }}</span>
        <span
          v-if="appointment.reschedules_count > 0"
          class="text-xs text-n-slate-10"
        >
          {{ rescheduleCountLabel(t, appointment.reschedules_count) }}
        </span>
        <div class="flex flex-wrap items-center gap-2 pt-1">
          <Select
            :model-value="appointment.status"
            :options="statusOptions"
            :disabled="updatingId === appointment.id"
            @update:model-value="status => setStatus(appointment, status)"
          />
          <Button
            size="sm"
            :variant="ACTION_BUTTON_VARIANT"
            :class="ACTION_BUTTON_CLASS"
            :color="RESCHEDULE_ACTION.color"
            :icon="RESCHEDULE_ACTION.icon"
            :label="t(RESCHEDULE_ACTION.labelKey)"
            @click="openRescheduleDrawer(appointment)"
          />
        </div>
      </div>
    </div>
    <p v-else class="text-sm text-n-slate-11">
      {{ t('CALENDARIO.CONTACT_APPOINTMENTS.EMPTY') }}
    </p>

    <AppointmentFormDrawer
      :show="showFormDrawer"
      :preset-contact="contact"
      :preset-conversation-id="conversationId"
      @close="closeFormDrawer"
      @created="refresh"
    />

    <RescheduleAppointmentDrawer
      :show="showRescheduleDrawer"
      :appointment="reschedulingAppointment"
      @close="closeRescheduleDrawer"
    />

    <CancelAppointmentDrawer
      :show="showCancelDrawer"
      :appointment="cancellingAppointment"
      @close="closeCancelDrawer"
      @cancelled="refresh"
    />
  </div>
</template>

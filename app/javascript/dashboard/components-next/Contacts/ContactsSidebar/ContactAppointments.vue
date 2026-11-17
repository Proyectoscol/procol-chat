<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import calendarioContactCreditsAPI from 'dashboard/api/calendarioContactCredits';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import AppointmentFormModal from 'dashboard/routes/dashboard/calendario/components/AppointmentFormModal.vue';
import RescheduleAppointmentModal from 'dashboard/routes/dashboard/calendario/components/RescheduleAppointmentModal.vue';
import CancelAppointmentModal from 'dashboard/routes/dashboard/calendario/components/CancelAppointmentModal.vue';
import {
  statusSelectOptions,
  statusRowBackgroundClass,
  RESCHEDULE_ACTION,
  rescheduleCountLabel,
  ACTION_BUTTON_VARIANT,
  ACTION_BUTTON_CLASS,
} from 'dashboard/routes/dashboard/calendario/helpers/appointmentStatusActions';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const appointments = useMapGetter(
  'calendarioAppointments/getContactAppointments'
);
const uiFlags = useMapGetter('calendarioAppointments/getUIFlags');
const isFetching = computed(() => uiFlags.value.isFetchingByContact);
const getContactById = useMapGetter('contacts/getContact');
const updatingId = ref(null);
const showRescheduleModal = ref(false);
const reschedulingAppointment = ref(null);
const showCancelModal = ref(false);
const cancellingAppointment = ref(null);
const showFormModal = ref(false);
const availableCredits = ref(0);

const presetContact = computed(() => {
  const contact = getContactById.value(route.params.contactId);
  return contact?.id ? { id: contact.id, name: contact.name } : null;
});

const refreshAppointments = () =>
  store.dispatch('calendarioAppointments/getByContact', route.params.contactId);
const openCreateModal = () => {
  showFormModal.value = true;
};
const closeFormModal = () => {
  showFormModal.value = false;
};

const statusOptions = computed(() => statusSelectOptions(t));

const formatDateTime = value =>
  new Date(value).toLocaleString(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  });

const openRescheduleModal = appointment => {
  reschedulingAppointment.value = appointment;
  showRescheduleModal.value = true;
};
const closeRescheduleModal = () => {
  showRescheduleModal.value = false;
};

const openCancelModal = appointment => {
  cancellingAppointment.value = appointment;
  showCancelModal.value = true;
};
const closeCancelModal = () => {
  showCancelModal.value = false;
};

const setStatus = async (appointment, status) => {
  if (status === 'cancelled') {
    openCancelModal(appointment);
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

onMounted(async () => {
  const { contactId } = route.params;
  if (!contactId) return;
  store.dispatch('calendarioAppointments/getByContact', contactId);
  try {
    const response = await calendarioContactCreditsAPI.getForContact(contactId);
    availableCredits.value = response.data.available_count;
  } catch (error) {
    availableCredits.value = 0;
  }
});
</script>

<template>
  <div class="flex items-center justify-end px-6 pt-4">
    <Button
      size="sm"
      icon="i-lucide-plus"
      :label="t('CALENDARIO.APPOINTMENTS.ADD_BUTTON')"
      @click="openCreateModal"
    />
  </div>
  <div
    v-if="isFetching"
    class="flex items-center justify-center py-10 text-n-slate-11"
  >
    <Spinner />
  </div>
  <div v-else-if="appointments.length" class="flex flex-col gap-2 px-6 py-4">
    <div
      v-if="availableCredits > 0"
      class="flex items-center gap-2 rounded-lg bg-n-teal-3 px-3 py-2 text-xs font-medium text-n-teal-11"
    >
      <span class="i-lucide-wallet size-4" />
      {{
        t('CALENDARIO.CONTACT_APPOINTMENTS.AVAILABLE_CREDITS', {
          count: availableCredits,
        })
      }}
    </div>
    <div
      v-for="appointment in appointments"
      :key="appointment.id"
      class="flex flex-col gap-1 rounded-xl border border-n-weak p-3"
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
          @click="openRescheduleModal(appointment)"
        />
      </div>
    </div>
  </div>
  <p v-else class="px-6 py-4 text-sm text-n-slate-11">
    {{ t('CALENDARIO.CONTACT_APPOINTMENTS.EMPTY') }}
  </p>

  <woot-modal
    v-model:show="showRescheduleModal"
    :on-close="closeRescheduleModal"
  >
    <RescheduleAppointmentModal
      v-if="reschedulingAppointment"
      :appointment="reschedulingAppointment"
      @close="closeRescheduleModal"
    />
  </woot-modal>

  <woot-modal v-model:show="showCancelModal" :on-close="closeCancelModal">
    <CancelAppointmentModal
      v-if="cancellingAppointment"
      :appointment="cancellingAppointment"
      @close="closeCancelModal"
    />
  </woot-modal>

  <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
    <AppointmentFormModal
      :preset-contact="presetContact"
      @close="closeFormModal"
      @created="refreshAppointments"
    />
  </woot-modal>
</template>

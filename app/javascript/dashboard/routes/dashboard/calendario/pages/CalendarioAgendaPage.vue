<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import RescheduleAppointmentModal from '../components/RescheduleAppointmentModal.vue';
import CancelAppointmentModal from '../components/CancelAppointmentModal.vue';
import AppointmentDetailModal from '../components/AppointmentDetailModal.vue';
import AppointmentRow from '../components/AppointmentRow.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const showRescheduleModal = ref(false);
const reschedulingAppointment = ref(null);
const showCancelModal = ref(false);
const cancellingAppointment = ref(null);
const showDetailModal = ref(false);
const selectedAppointmentId = ref(null);
const updatingAppointmentId = ref(null);

const appointments = useMapGetter(
  'calendarioAppointments/getAgendaAppointments'
);
const uiFlags = useMapGetter('calendarioAppointments/getUIFlags');
const accountId = useMapGetter('getCurrentAccountId');
const professionals = useMapGetter('calendarioProfessionals/getProfessionals');
const specialties = useMapGetter('calendarioSpecialties/getSpecialties');

// "Hoy" junta a todos los doctores en una sola lista -- a diferencia de
// Agendas (que ya separa por pestana de profesional), aqui hacen falta
// estos dos filtros para no tener que desplazarse por todos los grupos
// buscando uno solo.
const selectedSpecialties = ref([]);
const selectedProfessionals = ref([]);

const specialtyOptions = computed(() =>
  specialties.value.map(specialty => ({
    id: specialty.id,
    name: specialty.name,
  }))
);
// Opciones del filtro: solo profesionales activos -- uno archivado no
// deberia ofrecerse como filtro nuevo (aunque sus citas de hoy, si las
// tuviera, igual se siguen mostrando: ver specialtyIdForProfessional, que
// a proposito usa la lista COMPLETA para no perder esas citas del filtro
// por especialidad).
const professionalOptions = computed(() =>
  professionals.value
    .filter(professional => professional.active)
    .map(professional => ({ id: professional.id, name: professional.name }))
);

const specialtyIdForProfessional = professionalId =>
  professionals.value.find(p => p.id === professionalId)?.specialty_id;

const matchesFilters = appointment => {
  if (
    selectedSpecialties.value.length &&
    !selectedSpecialties.value.some(
      s => s.id === specialtyIdForProfessional(appointment.professional_id)
    )
  ) {
    return false;
  }
  if (
    selectedProfessionals.value.length &&
    !selectedProfessionals.value.some(p => p.id === appointment.professional_id)
  ) {
    return false;
  }
  return true;
};

const filteredAppointments = computed(() =>
  appointments.value.filter(matchesFilters)
);

// Misma tarjeta que Agendas (CalendarioSchedulesPage) -- esta vista solo
// cambia el agrupador: ahi es por franja horaria de UN profesional, aqui es
// por profesional porque "hoy" junta a los 5 doctores en un solo dia.
const groupedByProfessional = computed(() => {
  const groups = new Map();
  filteredAppointments.value.forEach(appointment => {
    const key = appointment.professional_id;
    if (!groups.has(key)) {
      groups.set(key, {
        professionalName: appointment.professional_name,
        appointments: [],
      });
    }
    groups.get(key).appointments.push(appointment);
  });
  groups.forEach(group => {
    group.appointments.sort(
      (a, b) => new Date(a.starts_at) - new Date(b.starts_at)
    );
  });
  return [...groups.values()].sort((a, b) =>
    a.professionalName.localeCompare(b.professionalName, 'es')
  );
});

const openConversation = appointment => {
  if (!appointment.conversation_id) return;
  router.push(
    frontendURL(
      conversationUrl({
        accountId: accountId.value,
        id: appointment.conversation_id,
      })
    )
  );
};

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

const openDetailModal = appointment => {
  selectedAppointmentId.value = appointment.id;
  showDetailModal.value = true;
};
const closeDetailModal = () => {
  showDetailModal.value = false;
};

const refresh = () => store.dispatch('calendarioAppointments/getAgenda');

const setStatus = async (appointment, status) => {
  if (status === 'cancelled') {
    openCancelModal(appointment);
    return;
  }
  updatingAppointmentId.value = appointment.id;
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
    updatingAppointmentId.value = null;
  }
};

onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('calendarioAppointments/getAgenda'),
      store.dispatch('calendarioProfessionals/get'),
      store.dispatch('calendarioSpecialties/get'),
    ]);
  } catch (error) {
    useAlert(t('CALENDARIO.AGENDA.FETCH_ERROR'));
  }
});
</script>

<template>
  <div
    v-if="uiFlags.isFetchingAgenda"
    class="flex items-center justify-center py-8"
  >
    <Spinner />
  </div>
  <div v-else class="flex flex-col gap-4">
    <p class="text-sm text-n-slate-11">
      {{ t('CALENDARIO.AGENDA.DESCRIPTION') }}
    </p>

    <div class="flex flex-wrap items-end gap-3">
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.AGENDA.FILTERS.SPECIALTY_LABEL')
        }}</label>
        <MultiSelect
          v-model="selectedSpecialties"
          :options="specialtyOptions"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.AGENDA.FILTERS.PROFESSIONAL_LABEL')
        }}</label>
        <MultiSelect
          v-model="selectedProfessionals"
          :options="professionalOptions"
        />
      </div>
    </div>

    <p
      v-if="!filteredAppointments.length"
      class="text-sm text-n-slate-10 text-center py-8"
    >
      {{ t('CALENDARIO.AGENDA.EMPTY') }}
    </p>
    <div v-else class="flex flex-col gap-3 rounded-xl border border-n-weak p-3">
      <div
        v-for="(group, index) in groupedByProfessional"
        :key="group.professionalName"
        class="flex flex-col gap-2"
        :class="index > 0 ? 'border-t border-n-weak pt-3' : ''"
      >
        <span class="font-medium text-n-slate-12">{{
          group.professionalName
        }}</span>

        <div class="flex flex-col divide-y divide-n-weak">
          <AppointmentRow
            v-for="appointment in group.appointments"
            :key="appointment.id"
            :appointment="appointment"
            :account-id="accountId"
            :updating="updatingAppointmentId === appointment.id"
            @open-detail="openDetailModal"
            @open-conversation="openConversation"
            @set-status="setStatus"
            @reschedule="openRescheduleModal"
          />
        </div>
      </div>
    </div>

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

    <woot-modal v-model:show="showDetailModal" :on-close="closeDetailModal">
      <AppointmentDetailModal
        v-if="selectedAppointmentId"
        :appointment-id="selectedAppointmentId"
        @close="closeDetailModal"
        @reschedule="openRescheduleModal"
        @cancel="openCancelModal"
        @changed="refresh"
      />
    </woot-modal>

    <woot-modal v-model:show="showCancelModal" :on-close="closeCancelModal">
      <CancelAppointmentModal
        v-if="cancellingAppointment"
        :appointment="cancellingAppointment"
        @close="closeCancelModal"
        @cancelled="refresh"
      />
    </woot-modal>
  </div>
</template>

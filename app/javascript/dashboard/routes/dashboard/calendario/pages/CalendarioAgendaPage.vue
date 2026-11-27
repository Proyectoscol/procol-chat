<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import RescheduleAppointmentModal from '../components/RescheduleAppointmentModal.vue';
import CancelAppointmentModal from '../components/CancelAppointmentModal.vue';
import AppointmentDetailModal from '../components/AppointmentDetailModal.vue';
import AppointmentFormModal from '../components/AppointmentFormModal.vue';
import AppointmentRow from '../components/AppointmentRow.vue';
import {
  dateKeyInColombia,
  formatDateOnlyEs,
  formatInstantTimeEs,
} from '../helpers/calendarioDateTime';

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
const showFormModal = ref(false);
const presetProfessionalId = ref(null);
const presetStartsAt = ref(null);

const appointments = useMapGetter(
  'calendarioAppointments/getAgendaAppointments'
);
const uiFlags = useMapGetter('calendarioAppointments/getUIFlags');
const accountId = useMapGetter('getCurrentAccountId');
const openDays = useMapGetter('calendarioOpenDays/getOpenDays');
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

// null = viendo hoy. Un string "YYYY-MM-DD" cuando se salto a "Siguiente
// dia con citas" (ver goToNextAgendaDay) -- se manda tal cual a la API
// (ver Api::V1::Accounts::Calendario::AppointmentsController#agenda_date),
// nunca se reconstruye como Date en el navegador para no arriesgar un
// corrimiento de zona horaria.
const viewedDate = ref(null);
const isLoadingNextDay = ref(false);

const todayKey = () => dateKeyInColombia(new Date().toISOString());
const isViewingToday = computed(
  () => !viewedDate.value || viewedDate.value === todayKey()
);
const viewedDateLabel = computed(() => {
  if (!viewedDate.value) return null;
  return formatDateOnlyEs(viewedDate.value, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });
});

const windowLabel = timeWindow =>
  t(`CALENDARIO.SCHEDULES.TIME_WINDOW.${timeWindow.toUpperCase()}`);

// Nota de "abrir agenda" (OpenDay) del dia que se esta viendo, por
// profesional -- pedido explicito del usuario: debe verse al lado del
// nombre del profesional en esta pagina, igual que ya se ve al lado de la
// fecha en Agendas (CalendarioSchedulesPage).
const openDayNotesByProfessional = computed(() => {
  const activeDate = viewedDate.value || todayKey();
  const notesByProfessional = new Map();
  openDays.value
    .filter(openDay => openDay.date === activeDate && openDay.notes)
    .forEach(openDay => {
      const existing = notesByProfessional.get(openDay.professional_id) || [];
      existing.push(openDay);
      notesByProfessional.set(openDay.professional_id, existing);
    });
  const result = new Map();
  notesByProfessional.forEach((entries, professionalId) => {
    result.set(
      professionalId,
      entries.length > 1
        ? entries
            .map(
              openDay => `${windowLabel(openDay.time_window)}: ${openDay.notes}`
            )
            .join(' · ')
        : entries[0].notes
    );
  });
  return result;
});

// Linea roja de "ahora" -- solo tiene sentido mirando el dia de hoy, nunca
// en "Siguiente dia con citas" (pedido explicito del usuario: "para que me
// quede facil guiarme en que paciente vamos", esto por profesional). Se
// recalcula cada minuto, no en cada render, para no generar timers
// invisibles costosos en una pagina que puede quedar abierta horas.
const now = ref(new Date());
let nowTimer = null;
onMounted(() => {
  nowTimer = setInterval(() => {
    now.value = new Date();
  }, 60000);
});
onUnmounted(() => {
  if (nowTimer) clearInterval(nowTimer);
});

// Indice donde insertar la linea roja dentro de las citas YA ordenadas de
// un profesional -- justo antes de la primera cita que todavia no deberia
// haber pasado. length = ya paso la ultima (linea al final); 0 = todavia no
// empieza ninguna (linea al inicio).
const nowLineIndexFor = group => {
  if (!isViewingToday.value) return -1;
  const index = group.appointments.findIndex(
    appointment => new Date(appointment.starts_at) > now.value
  );
  return index === -1 ? group.appointments.length : index;
};

// Misma tarjeta que Agendas (CalendarioSchedulesPage) -- esta vista solo
// cambia el agrupador: ahi es por franja horaria de UN profesional, aqui es
// por profesional porque "hoy" junta a los 5 doctores en un solo dia.
const groupedByProfessional = computed(() => {
  const groups = new Map();
  filteredAppointments.value.forEach(appointment => {
    const key = appointment.professional_id;
    if (!groups.has(key)) {
      groups.set(key, {
        professionalId: key,
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

const escapeHtml = value =>
  String(value ?? '').replace(
    /[&<>"']/g,
    char =>
      ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
      })[char]
  );

const statusLabel = status =>
  t(`CALENDARIO.APPOINTMENTS.STATUS.${status.toUpperCase()}`);

// Pedido explicito del usuario: "imprimir... cada profesional de forma
// organizada, uno debajo del otro... tipo Excel" -- una ventana nueva con
// una tabla simple por profesional (groupedByProfessional ya trae los
// datos en el orden/agrupacion correctos) y window.print(), en vez de
// pelear con el CSS de impresion del resto de la app. escapeHtml porque
// nombres de contacto/servicio son datos del usuario (no de este codigo)
// y van directo a innerHTML de la ventana nueva.
const printAgenda = () => {
  const dateLabel = isViewingToday.value
    ? formatDateOnlyEs(todayKey(), {
        weekday: 'long',
        day: 'numeric',
        month: 'long',
        year: 'numeric',
      })
    : viewedDateLabel.value;

  const sections = groupedByProfessional.value
    .map(
      group => `
        <h2>${escapeHtml(group.professionalName)}</h2>
        <table>
          <thead>
            <tr><th>Hora</th><th>Paciente</th><th>Servicio</th><th>Entidad</th><th>Estado</th></tr>
          </thead>
          <tbody>
            ${group.appointments
              .map(
                appointment => `
                  <tr>
                    <td>${formatInstantTimeEs(appointment.starts_at)}</td>
                    <td>${escapeHtml(appointment.contact_name)}</td>
                    <td>${escapeHtml(appointment.service_name)}</td>
                    <td>${escapeHtml(appointment.payer_name)}</td>
                    <td>${escapeHtml(statusLabel(appointment.status))}</td>
                  </tr>
                `
              )
              .join('')}
          </tbody>
        </table>
      `
    )
    .join('');

  const html = `
    <html>
      <head>
        <title>Agenda ${escapeHtml(dateLabel)}</title>
        <style>
          body { font-family: Arial, sans-serif; padding: 24px; color: #111; }
          h1 { font-size: 18px; margin-bottom: 4px; text-transform: capitalize; }
          h2 { font-size: 14px; margin-top: 24px; margin-bottom: 4px; border-bottom: 2px solid #333; padding-bottom: 2px; }
          table { width: 100%; border-collapse: collapse; margin-bottom: 8px; font-size: 12px; }
          th, td { border: 1px solid #ccc; padding: 4px 8px; text-align: left; }
          th { background: #f0f0f0; }
          @media print {
            h2 { page-break-after: avoid; }
            tr { page-break-inside: avoid; }
          }
        </style>
      </head>
      <body>
        <h1>Agenda ${escapeHtml(dateLabel)}</h1>
        ${sections || '<p>Sin citas para este dia.</p>'}
      </body>
    </html>
  `;

  const printWindow = window.open('', '_blank');
  if (!printWindow) return;
  printWindow.document.write(html);
  printWindow.document.close();
  printWindow.focus();
  printWindow.print();
};

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

// Mismo patron que CalendarioSchedulesPage (ideas.txt #8): la hora de la
// cita nueva no hay que escogerla, empieza justo cuando termina la
// anterior con el mismo profesional.
const openQuickBookAfter = appointment => {
  presetProfessionalId.value = appointment.professional_id;
  presetStartsAt.value = new Date(appointment.ends_at);
  showFormModal.value = true;
};
const closeFormModal = () => {
  showFormModal.value = false;
  presetProfessionalId.value = null;
  presetStartsAt.value = null;
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

const fetchAgenda = async () => {
  try {
    await store.dispatch('calendarioAppointments/getAgenda', viewedDate.value);
  } catch (error) {
    useAlert(t('CALENDARIO.AGENDA.FETCH_ERROR'));
  }
};
const refresh = fetchAgenda;

const goToNextAgendaDay = async () => {
  isLoadingNextDay.value = true;
  try {
    const nextDate = await store.dispatch(
      'calendarioAppointments/getNextAgendaDate'
    );
    if (!nextDate) {
      useAlert(t('CALENDARIO.AGENDA.NO_FUTURE_APPOINTMENTS'));
      return;
    }
    viewedDate.value = nextDate;
    await fetchAgenda();
  } catch (error) {
    useAlert(t('CALENDARIO.AGENDA.FETCH_ERROR'));
  } finally {
    isLoadingNextDay.value = false;
  }
};

const goToToday = async () => {
  viewedDate.value = null;
  await fetchAgenda();
};

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
      fetchAgenda(),
      store.dispatch('calendarioProfessionals/get'),
      store.dispatch('calendarioSpecialties/get'),
      // Sin professionalId -- esta vista junta a todos los doctores de un
      // mismo dia, asi que trae todos los dias abiertos de una sola vez
      // (ver openDaysNotesByProfessional, que filtra por fecha en memoria).
      store.dispatch('calendarioOpenDays/get'),
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
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p v-if="isViewingToday" class="text-sm text-n-slate-11">
        {{ t('CALENDARIO.AGENDA.DESCRIPTION') }}
      </p>
      <p
        v-else
        class="text-sm font-semibold text-n-slate-12 bg-n-amber-3 border border-n-amber-6 rounded-lg px-3 py-1.5"
      >
        {{ t('CALENDARIO.AGENDA.VIEWING_DATE', { date: viewedDateLabel }) }}
      </p>
      <div class="flex items-center gap-2">
        <Button
          v-if="!isViewingToday"
          faded
          slate
          sm
          :label="t('CALENDARIO.AGENDA.BACK_TO_TODAY')"
          @click="goToToday"
        />
        <Button
          v-if="isViewingToday"
          faded
          slate
          sm
          :is-loading="isLoadingNextDay"
          :label="t('CALENDARIO.AGENDA.NEXT_DAY_BUTTON')"
          @click="goToNextAgendaDay"
        />
      </div>
    </div>
    <div class="flex justify-end">
      <Button
        faded
        slate
        sm
        icon="i-lucide-printer"
        :label="t('CALENDARIO.AGENDA.PRINT_BUTTON')"
        @click="printAgenda"
      />
    </div>

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
        <div class="flex items-baseline gap-2 flex-wrap">
          <span class="font-medium text-n-slate-12">{{
            group.professionalName
          }}</span>
          <span
            v-if="openDayNotesByProfessional.get(group.professionalId)"
            class="text-xs text-n-slate-10"
          >
            {{ openDayNotesByProfessional.get(group.professionalId) }}
          </span>
        </div>

        <div class="flex flex-col divide-y divide-n-weak">
          <template
            v-for="(appointment, aptIndex) in group.appointments"
            :key="appointment.id"
          >
            <div
              v-if="aptIndex === nowLineIndexFor(group)"
              class="relative h-0 border-t-2 border-n-ruby-9 my-0.5"
            >
              <span
                class="absolute -top-2 ltr:right-0 rtl:left-0 px-1.5 rounded-full bg-n-ruby-9 text-white text-[10px] leading-4 font-medium"
              >
                {{ t('CALENDARIO.AGENDA.NOW_LINE_LABEL') }}
              </span>
            </div>
            <AppointmentRow
              :appointment="appointment"
              :account-id="accountId"
              :updating="updatingAppointmentId === appointment.id"
              @open-detail="openDetailModal"
              @open-conversation="openConversation"
              @set-status="setStatus"
              @reschedule="openRescheduleModal"
              @quick-book-after="openQuickBookAfter"
            />
          </template>
          <div
            v-if="nowLineIndexFor(group) === group.appointments.length"
            class="relative h-0 border-t-2 border-n-ruby-9 my-0.5"
          >
            <span
              class="absolute -top-2 ltr:right-0 rtl:left-0 px-1.5 rounded-full bg-n-ruby-9 text-white text-[10px] leading-4 font-medium"
            >
              {{ t('CALENDARIO.AGENDA.NOW_LINE_LABEL') }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <AppointmentFormModal
        :preset-professional-id="presetProfessionalId"
        :preset-starts-at="presetStartsAt"
        @close="closeFormModal"
        @created="refresh"
      />
    </woot-modal>

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

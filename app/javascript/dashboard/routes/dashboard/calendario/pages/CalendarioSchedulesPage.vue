<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CalendarioStatsAPI from 'dashboard/api/calendarioStats';
import AppointmentFormModal from '../components/AppointmentFormModal.vue';
import RescheduleAppointmentModal from '../components/RescheduleAppointmentModal.vue';
import CancelAppointmentModal from '../components/CancelAppointmentModal.vue';
import AppointmentDetailModal from '../components/AppointmentDetailModal.vue';
import OpenAgendaPanel from '../components/OpenAgendaPanel.vue';
import WaitlistPanel from '../components/WaitlistPanel.vue';
import WaitlistQuickBookPopover from '../components/WaitlistQuickBookPopover.vue';
import {
  statusSelectOptions,
  statusRowBackgroundClass,
  RESCHEDULE_ACTION,
  ACTION_BUTTON_VARIANT,
  ACTION_BUTTON_CLASS,
} from '../helpers/appointmentStatusActions';
import {
  dateKeyInColombia,
  formatDateOnlyEs,
  formatInstantTimeEs,
} from '../helpers/calendarioDateTime';
import { documentTypeAbbreviation } from '../helpers/documentTypeAbbreviation';

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const PAGE_SIZE = 10;
const WINDOW_ORDER = { morning: 0, afternoon: 1, full_day: 2 };

const professionals = useMapGetter('calendarioProfessionals/getProfessionals');
const openDays = useMapGetter('calendarioOpenDays/getOpenDays');
const waitlistEntries = useMapGetter(
  'calendarioWaitlistEntries/getWaitlistEntries'
);
const appointments = useMapGetter('calendarioAppointments/getAppointments');
const openDaysUiFlags = useMapGetter('calendarioOpenDays/getUIFlags');
const appointmentsUiFlags = useMapGetter('calendarioAppointments/getUIFlags');
const accountId = useMapGetter('getCurrentAccountId');
const services = useMapGetter('calendarioServices/getServices');
const payers = useMapGetter('calendarioPayers/getPayers');
const specialties = useMapGetter('calendarioSpecialties/getSpecialties');

// Acota la lista de pestanas de profesional por especialidad -- pedido
// explicito del usuario: "para que no me tenga una lista larga de
// doctores, sino que literalmente esté cambiando entre especialidad".
// Select simple (no multi) porque la idea es alternar entre UNA
// especialidad a la vez, no combinar varias.
const selectedSpecialtyId = ref('');
const specialtyFilterOptions = computed(() => [
  { value: '', label: t('CALENDARIO.SCHEDULES.FILTERS.SPECIALTY_ALL') },
  ...specialties.value.map(specialty => ({
    value: specialty.id,
    label: specialty.name,
  })),
]);
// Un profesional archivado (active: false) no aparece como pestaña aqui --
// pedido explicito del usuario: "al archivarlos ya no me los muestre en
// agendas". Sus citas/dias abiertos pasados no se borran, solo deja de
// poder gestionarselas desde esta pantalla.
const filteredProfessionals = computed(() => {
  const activeProfessionals = professionals.value.filter(p => p.active);
  return selectedSpecialtyId.value
    ? activeProfessionals.filter(
        p => p.specialty_id === selectedSpecialtyId.value
      )
    : activeProfessionals;
});

// El profesional ya se elige con las pestanas -- estos filtros se combinan
// con eso (ej. Dr. Corrales + Control + Particular) para poder armar vistas
// cruzadas sin salir de la pestana del profesional.
// Servicio es seleccion UNICA (no multi) a proposito: cuando Agendas esta
// expandida, este mismo valor se comparte con el filtro de la lista de
// espera en ambos sentidos -- cambiar en cualquiera de los dos lados
// cambia el otro (pedido explicito del usuario), algo que no es posible de
// forma simple con un multi-select de un lado y un select simple del otro.
const selectedServiceId = ref('');
const selectedPayers = ref([]);
const serviceFilterOptions = computed(() => [
  { value: '', label: t('CALENDARIO.SCHEDULES.FILTERS.SERVICE_ALL') },
  ...services.value.map(service => ({
    value: service.id,
    label: service.name,
  })),
]);
const payerFilterOptions = computed(() =>
  payers.value.map(payer => ({ id: payer.id, name: payer.name }))
);
const matchesFilters = appointment => {
  if (
    selectedServiceId.value &&
    appointment.service_id !== selectedServiceId.value
  ) {
    return false;
  }
  if (
    selectedPayers.value.length &&
    !selectedPayers.value.some(p => p.id === appointment.payer_id)
  ) {
    return false;
  }
  return true;
};

const activeProfessionalId = ref(null);
const visibleCount = ref(PAGE_SIZE);
const showRate = ref(null);

const showFormModal = ref(false);
const presetContact = ref(null);
const presetServiceId = ref(null);
const presetProfessionalId = ref(null);
const presetStartsAt = ref(null);

const showRescheduleModal = ref(false);
const reschedulingAppointment = ref(null);
const showCancelModal = ref(false);
const cancellingAppointment = ref(null);
const showDetailModal = ref(false);
const selectedAppointmentId = ref(null);

const showOpenAgendaPanel = ref(false);
const showWaitlistPanel = ref(false);
const updatingAppointmentId = ref(null);
const bottomSentinel = ref(null);

// --- Agendar rapido desde la lista de espera (modo expandido) -----------
// "Expandir" pone la lista de espera al lado de las agendas (en vez de
// como drawer superpuesto) y habilita "armar" una entrada para colocarla
// directamente sobre un dia ya abierto, sin pasar por el modal completo.
const isExpanded = ref(false);
const armedEntry = ref(null);
const openQuickBookWindow = ref(null);
const inlineWaitlistRef = ref(null);

const cancelArming = () => {
  armedEntry.value = null;
  openQuickBookWindow.value = null;
};
// Cambiar de profesional o colapsar la vista mientras algo esta armado lo
// cancela -- evita terminar agendando a alguien bajo el profesional
// equivocado.
watch(activeProfessionalId, cancelArming);
watch(isExpanded, cancelArming);

// "Expandir" es un modo de enfoque real -- pedido explicito del usuario:
// nada de sidebar, pestanas de Calendario, especialidad, servicio ni
// estadisticas, solo los dias abiertos y la lista de espera. Se saca del
// flujo normal del layout con Teleport a <body> (nadie en este codebase
// tiene ya un mecanismo para ocultar el sidebar global, y agregar uno
// nuevo en Dashboard.vue hubiera sido mucho mas invasivo que esto) y se
// bloquea el scroll de la pagina de atras mientras esta activo.
watch(isExpanded, expanded => {
  document.body.style.overflow = expanded ? 'hidden' : '';
});
onUnmounted(() => {
  document.body.style.overflow = '';
});

const pendingWaitlistCount = computed(() => waitlistEntries.value.length);

const activeProfessionalName = computed(
  () =>
    professionals.value.find(p => p.id === activeProfessionalId.value)?.name ||
    ''
);

const tabs = computed(() =>
  filteredProfessionals.value.map(professional => ({
    id: professional.id,
    label: professional.name,
  }))
);
const activeTabIndex = computed(() =>
  Math.max(
    0,
    filteredProfessionals.value.findIndex(
      p => p.id === activeProfessionalId.value
    )
  )
);

// Al cambiar de especialidad, si el profesional activo ya no esta en la
// lista acotada, salta al primero de la nueva lista -- sin esto, la pestana
// "activa" (por indice) podria terminar marcando un profesional distinto al
// que en realidad se esta mostrando.
watch(selectedSpecialtyId, () => {
  if (
    filteredProfessionals.value.length &&
    !filteredProfessionals.value.some(p => p.id === activeProfessionalId.value)
  ) {
    activeProfessionalId.value = filteredProfessionals.value[0].id;
  }
});

const allAppointmentsForOpenDay = openDay =>
  appointments.value
    .filter(a => dateKeyInColombia(a.starts_at) === openDay.date)
    .sort((a, b) => new Date(a.starts_at) - new Date(b.starts_at));

const appointmentsForOpenDay = openDay =>
  allAppointmentsForOpenDay(openDay).filter(matchesFilters);

// Distingue "de verdad no hay citas" de "hay citas pero los filtros las
// esconden" -- sin esto, un dia con citas que no calzan con el filtro
// mostraria por error "Agenda abierta, todavia sin citas".
const isHiddenByFilters = openDay =>
  allAppointmentsForOpenDay(openDay).length > 0 &&
  appointmentsForOpenDay(openDay).length === 0;

// Un mismo dia puede tener dos OpenDay (manana + tarde) -- se agrupan bajo
// un solo encabezado de fecha con una sub-seccion por franja, en vez de dos
// tarjetas sueltas que repiten la fecha. Orden ascendente (mas antiguo
// arriba, mas reciente abajo) a proposito -- la asistente viene del Excel,
// donde siempre trabajo asi, y cambiarle el sentido del scroll le
// rompería el habito. Lo "reciente primero" se logra mostrando solo la
// cola mas nueva del arreglo y arrancando la pagina con scroll al fondo
// (ver fetchForActiveProfessional), no invirtiendo el orden.
const groupedByDate = computed(() => {
  const groups = new Map();
  openDays.value.forEach(openDay => {
    if (!groups.has(openDay.date)) groups.set(openDay.date, []);
    groups.get(openDay.date).push(openDay);
  });
  return [...groups.entries()]
    .map(([date, entries]) => ({
      date,
      openDaysForDate: [...entries].sort(
        (a, b) => WINDOW_ORDER[a.time_window] - WINDOW_ORDER[b.time_window]
      ),
    }))
    .sort((a, b) => a.date.localeCompare(b.date));
});

// Cola del arreglo (las fechas mas nuevas) -- "cargar mas" extiende hacia
// atras y el boton vive arriba de la lista, no abajo.
const visibleDateGroups = computed(() =>
  groupedByDate.value.slice(-visibleCount.value)
);
const hasMoreOpenDays = computed(
  () => visibleCount.value < groupedByDate.value.length
);
const loadMore = () => {
  visibleCount.value += PAGE_SIZE;
};

const formatOpenDayDate = dateString =>
  formatDateOnlyEs(dateString, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });

const windowLabel = timeWindow =>
  t(`CALENDARIO.SCHEDULES.TIME_WINDOW.${timeWindow.toUpperCase()}`);

const statusLabel = status =>
  t(`CALENDARIO.APPOINTMENTS.STATUS.${status.toUpperCase()}`);

const statusOptions = computed(() => statusSelectOptions(t));

const contactUrl = appointment =>
  frontendURL(`accounts/${accountId.value}/contacts/${appointment.contact_id}`);

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

const resetPresets = () => {
  presetContact.value = null;
  presetServiceId.value = null;
  presetProfessionalId.value = null;
  presetStartsAt.value = null;
};

// Unica puerta de entrada para crear una cita -- cada tarjeta de dia abierto
// trae su propio boton "Agregar cita", a proposito no hay un boton generico
// en la parte superior: crear sin pasar por un dia abierto desordenaria la
// vista que reemplaza al Excel.
const openCreateForOpenDay = openDay => {
  resetPresets();
  const [y, m, d] = openDay.date.split('-').map(Number);
  presetStartsAt.value = new Date(y, m - 1, d, 8, 0);
  presetProfessionalId.value = openDay.professional_id;
  showFormModal.value = true;
};

const closeFormModal = () => {
  showFormModal.value = false;
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

const fetchForActiveProfessional = async () => {
  const professionalId = activeProfessionalId.value;
  if (!professionalId) return;
  visibleCount.value = PAGE_SIZE;

  const since = new Date();
  since.setFullYear(since.getFullYear() - 3);
  const until = new Date();
  until.setFullYear(until.getFullYear() + 1);

  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  await Promise.all([
    store.dispatch('calendarioOpenDays/get', { professionalId }),
    store.dispatch('calendarioAppointments/getRange', {
      since: since.toISOString(),
      until: until.toISOString(),
      professionalId,
    }),
    // Se necesita aqui (no solo cuando se abre el panel) para que el
    // mensaje vacio de "sin agenda abierta" pueda distinguir "de verdad no
    // hay nada" de "no hay agenda todavia, pero SI hay gente esperando" --
    // ej. Maria (Urodinamia) tiene 0 dias abiertos pero 109 en espera, y
    // antes el mensaje no lo dejaba ver.
    store.dispatch('calendarioWaitlistEntries/get', { professionalId }),
  ]);

  try {
    const response = await CalendarioStatsAPI.get({
      since: thirtyDaysAgo.toISOString(),
      until: new Date().toISOString(),
      professionalId,
    });
    showRate.value = response.data.summary;
  } catch (error) {
    showRate.value = null;
  }

  // Al entrar (o cambiar de profesional) el scroll arranca mostrando lo mas
  // reciente -- igual que la chica lo ve siempre en el Excel -- pero el
  // orden de la lista se mantiene antiguo-arriba/reciente-abajo para poder
  // seguir haciendo scroll hacia arriba y ver fechas pasadas.
  nextTick(() => {
    bottomSentinel.value?.scrollIntoView({ block: 'end' });
  });
};

const onTabChanged = tab => {
  activeProfessionalId.value = tab.id;
};

watch(activeProfessionalId, fetchForActiveProfessional);

const refresh = fetchForActiveProfessional;

const onOpenDayCreated = refresh;
const closeOpenAgendaPanel = () => {
  showOpenAgendaPanel.value = false;
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

const bookFromWaitlist = entry => {
  resetPresets();
  presetContact.value = { id: entry.contact_id, name: entry.contact_name };
  presetServiceId.value = entry.service_id;
  presetProfessionalId.value = entry.professional_id;
  showWaitlistPanel.value = false;
  showFormModal.value = true;
};

// En modo expandido, "Agendar" arma la entrada en vez de abrir el modal
// completo -- el usuario elige el dia haciendo click en "Agendar aqui" de
// una tarjeta ya abierta. Fuera de ese modo, el comportamiento es el de
// siempre (abre el modal).
const onWaitlistBook = entry => {
  if (isExpanded.value) {
    armedEntry.value = entry;
    openQuickBookWindow.value = null;
  } else {
    bookFromWaitlist(entry);
  }
};

// La hora de apertura "oficial" de cada ventana -- el modal completo
// siempre usa 8:00 para cualquier ventana (simplificacion vieja, sin
// tocar); el popover nuevo si distingue tarde de manana/todo el dia.
const defaultTimeForWindow = timeWindow =>
  timeWindow === 'afternoon' ? '14:00' : '08:00';

const onQuickBooked = async () => {
  cancelArming();
  await refresh();
  await inlineWaitlistRef.value?.fetchEntries();
};

const exportCsv = () => {
  const professionalName =
    professionals.value.find(p => p.id === activeProfessionalId.value)?.name ||
    '';
  const headers = [
    t('CALENDARIO.SCHEDULES.CSV.DATE'),
    t('CALENDARIO.SCHEDULES.CSV.TIME'),
    t('CALENDARIO.SCHEDULES.CSV.CONTACT'),
    t('CALENDARIO.SCHEDULES.CSV.DOCUMENT'),
    t('CALENDARIO.SCHEDULES.CSV.PHONE'),
    t('CALENDARIO.SCHEDULES.CSV.SERVICE'),
    t('CALENDARIO.SCHEDULES.CSV.PAYER'),
    t('CALENDARIO.SCHEDULES.CSV.STATUS'),
    t('CALENDARIO.SCHEDULES.CSV.NOTES'),
  ];
  const sorted = [...appointments.value].sort(
    (a, b) => new Date(a.starts_at) - new Date(b.starts_at)
  );
  const escapeCsv = value => `"${String(value ?? '').replace(/"/g, '""')}"`;
  const rows = sorted.map(appointment =>
    [
      dateKeyInColombia(appointment.starts_at),
      formatInstantTimeEs(appointment.starts_at),
      appointment.contact_name,
      appointment.contact_identifier,
      appointment.contact_phone_number,
      appointment.service_name,
      appointment.payer_name,
      statusLabel(appointment.status),
      appointment.notes,
    ]
      .map(escapeCsv)
      .join(',')
  );
  const content = [headers.map(escapeCsv).join(','), ...rows].join('\n');
  downloadCsvFile(`${professionalName}-agenda.csv`, content);
};

onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('calendarioProfessionals/get'),
      store.dispatch('calendarioServices/get'),
      store.dispatch('calendarioPayers/get'),
      store.dispatch('calendarioSpecialties/get'),
    ]);
    if (filteredProfessionals.value.length) {
      activeProfessionalId.value = filteredProfessionals.value[0].id;
    }
  } catch (error) {
    useAlert(t('CALENDARIO.SCHEDULES.FETCH_ERROR'));
  }
});
</script>

<template>
  <div class="h-full flex flex-col gap-4 min-h-0">
    <template v-if="!isExpanded">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <p class="text-sm text-n-slate-11">
          {{ t('CALENDARIO.SCHEDULES.DESCRIPTION') }}
        </p>
        <div class="flex items-center gap-2">
          <!-- Burbuja con el total de esta profesional -- pedido explicito
          del usuario: poder ver de un vistazo cuantos hay esperando sin
          tener que abrir el panel. relative/absolute porque Button no
          tiene un slot de badge propio. -->
          <div class="relative">
            <Button
              faded
              slate
              size="sm"
              :label="t('CALENDARIO.WAITLIST.OPEN_BUTTON')"
              @click="showWaitlistPanel = true"
            />
            <span
              v-if="pendingWaitlistCount"
              class="absolute -top-1.5 -right-1.5 flex items-center justify-center min-w-[18px] h-[18px] px-1 rounded-full bg-n-ruby-9 text-white text-[10px] font-medium leading-none"
            >
              {{ pendingWaitlistCount }}
            </span>
          </div>
          <Button
            faded
            slate
            size="sm"
            :label="t('CALENDARIO.SCHEDULES.EXPAND_BUTTON')"
            @click="isExpanded = true"
          />
        </div>
      </div>

      <div class="flex flex-col gap-1 w-fit">
        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.SCHEDULES.FILTERS.SPECIALTY_LABEL')
        }}</label>
        <Select
          v-model="selectedSpecialtyId"
          :options="specialtyFilterOptions"
        />
      </div>

      <TabBar
        v-if="tabs.length"
        :tabs="tabs"
        :initial-active-tab="activeTabIndex"
        @tab-changed="onTabChanged"
      />

      <div class="flex flex-wrap items-end gap-3">
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">{{
            t('CALENDARIO.SCHEDULES.FILTERS.SERVICE_LABEL')
          }}</label>
          <Select v-model="selectedServiceId" :options="serviceFilterOptions" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">{{
            t('CALENDARIO.SCHEDULES.FILTERS.PAYER_LABEL')
          }}</label>
          <MultiSelect v-model="selectedPayers" :options="payerFilterOptions" />
        </div>
      </div>

      <div v-if="showRate" class="flex flex-wrap items-center gap-3">
        <div class="flex flex-col gap-1 rounded-xl border border-n-weak p-3">
          <span class="text-xs text-n-slate-11">{{
            t('CALENDARIO.SCHEDULES.SHOW_RATE_LABEL')
          }}</span>
          <span class="text-xl font-semibold text-n-slate-12"
            >{{ showRate.attended_pct }}%</span
          >
        </div>
        <div class="flex flex-col gap-1 rounded-xl border border-n-weak p-3">
          <span class="text-xs text-n-slate-11">{{
            t('CALENDARIO.STATS.NO_SHOW_PCT')
          }}</span>
          <span class="text-xl font-semibold text-n-slate-12"
            >{{ showRate.no_show_pct }}%</span
          >
        </div>
        <Button
          faded
          slate
          size="sm"
          icon="i-lucide-download"
          :label="t('CALENDARIO.SCHEDULES.CSV.BUTTON')"
          :disabled="!appointments.length"
          @click="exportCsv"
        />
      </div>
    </template>

    <!-- Expandida, esto se teletransporta fuera de todo el layout normal
    (sidebar de Chatwoot, pestanas de Calendario, filtros de esta pagina) a
    un overlay de pantalla completa -- pedido explicito del usuario: "ya no
    me interesa ni el panel lateral, ni el boton de agenda por profesional,
    ni especialidad, ni servicio, ni estadisticas... literalmente solo
    quiero ver la agenda de los dias en un lado y en el otro la lista de
    espera". No existe ya un mecanismo en este codebase para ocultar el
    sidebar global, y agregar uno (estado compartido leido por
    Dashboard.vue) hubiera sido mucho mas invasivo que simplemente teletransportar
    este bloque a <body> con un z-index alto. -->
    <Teleport to="body" :disabled="!isExpanded">
      <div
        :class="
          isExpanded
            ? 'fixed inset-0 z-[100] bg-n-surface-1 p-4 flex flex-col gap-3'
            : 'flex-1 min-h-0 flex flex-col gap-3'
        "
      >
        <div v-if="isExpanded" class="flex items-center justify-between">
          <span class="text-sm font-medium text-n-slate-12">
            {{ activeProfessionalName }}
          </span>
          <Button
            faded
            slate
            size="sm"
            :label="t('CALENDARIO.SCHEDULES.COLLAPSE_BUTTON')"
            @click="isExpanded = false"
          />
        </div>

        <div
          v-if="openDaysUiFlags.isFetching || appointmentsUiFlags.isFetching"
          class="flex items-center justify-center py-8"
        >
          <Spinner />
        </div>
        <!-- flex-1 + min-h-0: esta seccion absorbe TODO el alto restante de la
        pantalla (sin scroll de pagina, pedido explicito) -- adentro, solo la
        tarjeta de dias (tambien flex-1 min-h-0) se encoge/expande y hace scroll
        por su cuenta; el boton de abrir agenda y su panel quedan con su alto
        natural, siempre visibles debajo. Expandida, la lista de espera vive al
        lado como segunda columna de esta misma fila, en vez de como drawer. -->
        <div v-else class="flex-1 min-h-0 flex flex-row gap-3">
          <!-- Si hay alguien armado, el banner queda fijo arriba de los dias --
      explica que esta pasando y permite cancelar sin tener que buscar la
      entrada de nuevo en la lista de espera. -->
          <div class="flex-1 min-h-0 flex flex-col gap-3">
            <div
              v-if="armedEntry"
              class="flex items-center justify-between gap-2 rounded-lg bg-n-amber-3 text-n-amber-11 px-3 py-2"
            >
              <span class="text-sm">
                {{
                  t('CALENDARIO.WAITLIST.QUICK_BOOK.ARMED_BANNER', {
                    name: armedEntry.contact_name,
                  })
                }}
              </span>
              <Button
                faded
                slate
                size="sm"
                :label="t('CALENDARIO.WAITLIST.QUICK_BOOK.CANCEL')"
                @click="cancelArming"
              />
            </div>
            <!-- Una sola tarjeta envuelve todos los dias -- el scroll (y el
        "cargar mas" de arriba) ocurre adentro de este contenedor, no de la
        pagina completa, para que el resto de la pantalla (profesionales,
        asistencia, CSV) quede siempre visible mientras se revisan fechas. -->
            <div
              class="flex-1 min-h-0 flex flex-col gap-3 rounded-xl border border-n-weak p-3 overflow-y-auto"
            >
              <div
                v-if="!openDays.length"
                class="flex flex-col items-center gap-2 text-center py-8"
              >
                <p class="text-sm text-n-slate-10">
                  {{ t('CALENDARIO.SCHEDULES.EMPTY') }}
                </p>
                <p v-if="pendingWaitlistCount" class="text-sm text-n-slate-11">
                  {{
                    t('CALENDARIO.SCHEDULES.EMPTY_WITH_WAITLIST', {
                      count: pendingWaitlistCount,
                    })
                  }}
                </p>
                <Button
                  v-if="pendingWaitlistCount"
                  faded
                  slate
                  size="sm"
                  :label="t('CALENDARIO.WAITLIST.OPEN_BUTTON')"
                  @click="showWaitlistPanel = true"
                />
              </div>

              <!-- Arriba de la lista: aqui vive "cargar mas" porque la lista va
        antiguo-arriba/reciente-abajo (igual que el Excel) -- extender hacia
        el pasado agrega tarjetas arriba, no abajo. -->
              <div v-if="hasMoreOpenDays" class="flex justify-center">
                <Button
                  faded
                  slate
                  size="sm"
                  :label="t('CALENDARIO.SCHEDULES.LOAD_MORE')"
                  @click="loadMore"
                />
              </div>

              <div
                v-for="group in visibleDateGroups"
                :key="group.date"
                class="flex flex-col gap-3 rounded-xl border border-n-weak p-3"
              >
                <span class="font-medium text-n-slate-12 capitalize">{{
                  formatOpenDayDate(group.date)
                }}</span>

                <div
                  v-for="(openDay, index) in group.openDaysForDate"
                  :key="openDay.id"
                  class="flex flex-col gap-2"
                  :class="index > 0 ? 'border-t border-n-weak pt-3' : ''"
                >
                  <div
                    class="flex items-center justify-between flex-wrap gap-2"
                  >
                    <span
                      class="text-xs font-medium text-n-slate-11 uppercase tracking-wide"
                    >
                      {{ windowLabel(openDay.time_window) }}
                    </span>
                    <div class="flex items-center gap-2">
                      <Button
                        v-if="armedEntry"
                        size="sm"
                        :label="
                          t('CALENDARIO.SCHEDULES.BOOK_HERE_BUTTON', {
                            name: armedEntry.contact_name,
                          })
                        "
                        @click="openQuickBookWindow = openDay.id"
                      />
                      <Button
                        faded
                        slate
                        size="sm"
                        icon="i-lucide-plus"
                        :label="
                          t('CALENDARIO.SCHEDULES.ADD_APPOINTMENT_BUTTON')
                        "
                        @click="openCreateForOpenDay(openDay)"
                      />
                    </div>
                  </div>
                  <p v-if="openDay.notes" class="text-xs text-n-slate-10">
                    {{ openDay.notes }}
                  </p>

                  <WaitlistQuickBookPopover
                    v-if="armedEntry && openQuickBookWindow === openDay.id"
                    :armed-entry="armedEntry"
                    :date="openDay.date"
                    :default-time="defaultTimeForWindow(openDay.time_window)"
                    @cancel="openQuickBookWindow = null"
                    @booked="onQuickBooked"
                  />

                  <div
                    v-if="appointmentsForOpenDay(openDay).length"
                    class="flex flex-col divide-y divide-n-weak"
                  >
                    <div
                      v-for="appointment in appointmentsForOpenDay(openDay)"
                      :key="appointment.id"
                      class="flex items-center justify-between gap-2 py-2 cursor-pointer hover:bg-n-alpha-1 rounded-lg px-1"
                      :class="statusRowBackgroundClass(appointment.status)"
                      @click="openDetailModal(appointment)"
                    >
                      <div
                        class="flex flex-wrap items-center gap-x-2 gap-y-0.5 min-w-0"
                      >
                        <span class="text-xs text-n-slate-10 w-14 shrink-0">{{
                          formatInstantTimeEs(appointment.starts_at)
                        }}</span>
                        <router-link
                          :to="contactUrl(appointment)"
                          class="text-sm hover:underline text-n-blue-text truncate"
                          @click.stop
                        >
                          {{ appointment.contact_name }}
                        </router-link>
                        <span
                          v-if="appointment.contact_identifier"
                          class="text-xs text-n-slate-10 truncate"
                        >
                          {{
                            documentTypeAbbreviation(
                              appointment.contact_document_type
                            )
                          }}
                          {{ appointment.contact_identifier }}
                        </span>
                        <a
                          v-if="appointment.contact_phone_number"
                          :href="`tel:${appointment.contact_phone_number}`"
                          class="text-xs text-n-slate-10 hover:text-n-teal-9 hover:underline shrink-0"
                          @click.stop
                        >
                          {{ appointment.contact_phone_number }}
                        </a>
                        <a
                          v-if="appointment.contact_secondary_phone_number"
                          :href="`tel:${appointment.contact_secondary_phone_number}`"
                          class="text-xs text-n-slate-10 hover:text-n-teal-9 hover:underline shrink-0"
                          @click.stop
                        >
                          {{ appointment.contact_secondary_phone_number }}
                        </a>
                        <button
                          v-if="appointment.conversation_id"
                          type="button"
                          class="i-lucide-message-circle size-4 text-n-slate-10 hover:text-n-blue-text shrink-0"
                          @click.stop="openConversation(appointment)"
                        />
                        <span class="text-xs text-n-slate-10 truncate">{{
                          appointment.service_name
                        }}</span>
                        <span
                          v-if="appointment.payer_name"
                          class="text-xs text-n-slate-10 truncate before:content-['·'] before:mr-2"
                        >
                          {{ appointment.payer_name }}
                        </span>
                      </div>
                      <div class="flex items-center gap-2 shrink-0" @click.stop>
                        <Select
                          :model-value="appointment.status"
                          :options="statusOptions"
                          :disabled="updatingAppointmentId === appointment.id"
                          @update:model-value="
                            status => setStatus(appointment, status)
                          "
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
                  <p v-else class="text-xs text-n-slate-10 italic">
                    {{
                      isHiddenByFilters(openDay)
                        ? t('CALENDARIO.SCHEDULES.HIDDEN_BY_FILTERS')
                        : t('CALENDARIO.SCHEDULES.EMPTY_OPEN_DAY')
                    }}
                  </p>
                </div>
              </div>

              <!-- Ancla invisible solo para el auto-scroll al fondo (ver
        fetchForActiveProfessional) -- el boton de abrir agenda ya no vive
        aqui adentro, pero el scroll-to-bottom si sigue necesitando un punto
        de referencia dentro del area con scroll. -->
              <div ref="bottomSentinel" class="h-px" />
            </div>

            <!-- Fuera de la tarjeta con scroll: el panel se despliega hacia arriba
      sobre este boton y no tiene sentido que quede encerrado en el area que
      se desplaza. -->
            <OpenAgendaPanel
              v-if="showOpenAgendaPanel && activeProfessionalId"
              :professional-id="activeProfessionalId"
              @close="closeOpenAgendaPanel"
              @created="onOpenDayCreated"
            />
            <div class="flex justify-center">
              <Button
                faded
                slate
                size="sm"
                icon="i-lucide-calendar-plus"
                :label="t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.BUTTON')"
                :disabled="!activeProfessionalId"
                @click="showOpenAgendaPanel = !showOpenAgendaPanel"
              />
            </div>
          </div>

          <WaitlistPanel
            v-if="isExpanded"
            ref="inlineWaitlistRef"
            inline
            show
            :professional-id="activeProfessionalId"
            :service-id="selectedServiceId"
            @update:service-id="selectedServiceId = $event"
            @book="onWaitlistBook"
          />
        </div>
      </div>
    </Teleport>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <AppointmentFormModal
        :preset-contact="presetContact"
        :preset-service-id="presetServiceId"
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

    <woot-modal v-model:show="showCancelModal" :on-close="closeCancelModal">
      <CancelAppointmentModal
        v-if="cancellingAppointment"
        :appointment="cancellingAppointment"
        @close="closeCancelModal"
        @cancelled="refresh"
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

    <WaitlistPanel
      v-if="!isExpanded"
      :show="showWaitlistPanel"
      :professional-id="activeProfessionalId"
      @close="showWaitlistPanel = false"
      @book="onWaitlistBook"
    />
  </div>
</template>

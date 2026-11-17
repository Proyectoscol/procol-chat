<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import FullCalendar from '@fullcalendar/vue3';
import timeGridPlugin from '@fullcalendar/timegrid';
import resourceTimeGridPlugin from '@fullcalendar/resource-timegrid';
import interactionPlugin from '@fullcalendar/interaction';
import esLocale from '@fullcalendar/core/locales/es';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';
import AppointmentFormModal from '../components/AppointmentFormModal.vue';
import RescheduleAppointmentModal from '../components/RescheduleAppointmentModal.vue';
import CancelAppointmentModal from '../components/CancelAppointmentModal.vue';
import AppointmentDetailModal from '../components/AppointmentDetailModal.vue';
import { statusEventColor } from '../helpers/appointmentStatusActions';
import {
  professionalColor,
  readableTextColor,
} from '../helpers/professionalColor';

const { t } = useI18n();
const store = useStore();

const appointments = useMapGetter('calendarioAppointments/getAppointments');
const professionals = useMapGetter('calendarioProfessionals/getProfessionals');
const services = useMapGetter('calendarioServices/getServices');
const payers = useMapGetter('calendarioPayers/getPayers');
const specialties = useMapGetter('calendarioSpecialties/getSpecialties');

const showFormModal = ref(false);
const presetStartsAt = ref(null);
const presetProfessionalId = ref(null);
const showDetailModal = ref(false);
const selectedAppointmentId = ref(null);
const showRescheduleModal = ref(false);
const reschedulingAppointment = ref(null);
const showCancelModal = ref(false);
const cancellingAppointment = ref(null);

// --- Filtros cruzados (especialidad x profesional x servicio x EPS) ------
// Los cuatro se combinan con AND entre si (ej. Urología + Corrales +
// Control) y con OR adentro de cada uno (ej. Control o Consulta) -- asi se
// puede armar cualquier vista que el personal necesite sin tener que ir
// pantalla por pantalla.
const selectedSpecialties = ref([]);
const selectedProfessionals = ref([]);
const selectedServices = ref([]);
const selectedPayers = ref([]);

const specialtyOptions = computed(() =>
  specialties.value.map(specialty => ({
    id: specialty.id,
    name: specialty.name,
  }))
);
// Opciones del filtro: solo profesionales activos -- uno archivado no
// deberia ofrecerse como filtro nuevo (specialtyIdForProfessional abajo usa
// a proposito la lista COMPLETA para no perder del filtro por especialidad
// las citas ya existentes de un profesional archivado).
const professionalOptions = computed(() =>
  professionals.value
    .filter(professional => professional.active)
    .map(professional => ({ id: professional.id, name: professional.name }))
);
const serviceOptions = computed(() =>
  services.value.map(service => ({ id: service.id, name: service.name }))
);
const payerOptions = computed(() =>
  payers.value.map(payer => ({ id: payer.id, name: payer.name }))
);

// La cita solo trae professional_id -- la especialidad se resuelve
// buscando el profesional correspondiente, no viaja duplicada en cada cita.
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
  if (
    selectedServices.value.length &&
    !selectedServices.value.some(s => s.id === appointment.service_id)
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

// Dos colores por tarjeta, pedido explicito del usuario (que se vea "como
// un calendario normal", ej. Google Calendar): el FONDO es el color del
// PROFESIONAL (para reconocer de un vistazo de quien es la cita, incluso
// en la vista "Semana" donde varios profesionales comparten el mismo dia);
// la etiqueta/punto interno es el color del SERVICIO, el mismo que se
// configura en /calendario/services. El estado (pendiente/confirmada/
// atendida/cancelada) ya no pinta el fondo ACA -- eso sigue siendo el
// criterio en Citas/Agenda/Contacto (ver appointmentStatusActions.js), que
// no se toca -- aqui el estado se ve en el borde de la tarjeta.
//
// resourceId: sin esto, FullCalendar apila en la MISMA columna de dia todas
// las citas de todos los profesionales que caen a la misma hora -- con 5-8
// profesionales cada uno con su propia agenda de 15-20 min, eso produce
// columnas tan angostas que el texto queda ilegible/superpuesto (el bug
// reportado). Con resourceId cada profesional tiene su propia columna en
// la vista "Dia"; en "Semana" (sin resources) se ignora sin problema.
const events = computed(() =>
  appointments.value.filter(matchesFilters).map(appointment => {
    const { border } = statusEventColor(appointment.status);
    const service = services.value.find(s => s.id === appointment.service_id);
    const background = professionalColor(
      appointment.professional_id,
      professionalOptions.value
    );
    return {
      id: appointment.id,
      resourceId: String(appointment.professional_id),
      title: `${appointment.contact_name} · ${appointment.service_name}`,
      start: appointment.starts_at,
      end: appointment.ends_at,
      backgroundColor: background,
      borderColor: border,
      textColor: readableTextColor(background),
      extendedProps: {
        serviceColor: service?.color || '#A5A5A5',
        serviceName: appointment.service_name,
        contactName: appointment.contact_name,
      },
    };
  })
);

// Recursos (columnas) del calendario: un profesional por columna. Si hay
// filtro de profesional activo, solo se muestran esos -- si no, todos los
// activos (igual criterio que professionalOptions de arriba).
const resources = computed(() =>
  (selectedProfessionals.value.length
    ? selectedProfessionals.value
    : professionalOptions.value
  ).map(p => ({ id: String(p.id), title: p.name }))
);

const openDetailModal = appointmentId => {
  selectedAppointmentId.value = appointmentId;
  showDetailModal.value = true;
};
const closeDetailModal = () => {
  showDetailModal.value = false;
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

// Antes esto se traia UNA sola vez al montar, siempre -7/+60 dias desde
// "hoy" -- al navegar con las flechas prev/next de FullCalendar a una
// semana fuera de esa ventana (ej. "26 oct - 1 nov" viendo desde el 14 de
// nov), la vista quedaba vacia aunque SI hubiera citas esa semana, porque
// nunca se habian pedido al backend. datesSet dispara cada vez que cambia
// el rango visible (prev/next/today/cambio de vista, incluido el render
// inicial) con el rango EXACTO que FullCalendar esta mostrando, asi que
// pedir datos ahi mantiene siempre cargado lo que el usuario esta viendo.
const lastFetchedRange = ref(null);

const fetchRange = async (since, until) => {
  lastFetchedRange.value = { since, until };
  try {
    await store.dispatch('calendarioAppointments/getRange', {
      since: since.toISOString(),
      until: until.toISOString(),
    });
  } catch (error) {
    useAlert(t('CALENDARIO.CALENDAR.FETCH_ERROR'));
  }
};

// Para refrescar despues de crear/cancelar/reagendar una cita -- repite el
// mismo rango que ya esta visible, sin necesidad de volver a preguntarle a
// FullCalendar cual es.
const refreshVisibleRange = () => {
  if (!lastFetchedRange.value) return;
  fetchRange(lastFetchedRange.value.since, lastFetchedRange.value.until);
};

const calendarOptions = computed(() => ({
  plugins: [timeGridPlugin, resourceTimeGridPlugin, interactionPlugin],
  // Una columna por profesional (ver "resources"/"resourceId" arriba) -- sin
  // esto, las citas de todos los profesionales a la misma hora se apilaban
  // en una sola columna angosta e ilegible (el bug reportado). "Dia" agrupa
  // por profesional para trabajar la agenda de hoy; "Semana" (sin recursos,
  // pedido explicito del usuario como vista por defecto) sirve para una
  // vista general rapida, igual que el calendario semanal de Google.
  initialView: 'timeGridWeek',
  resources: resources.value,
  locale: esLocale,
  headerToolbar: {
    left: 'prev,next today',
    center: 'title',
    right: 'resourceTimeGridDay,timeGridWeek',
  },
  buttonText: { resourceTimeGridDay: 'Día', timeGridWeek: 'Semana' },
  allDaySlot: false,
  // Horario real del consultorio (7am-6pm) -- antes se mostraban las 24h,
  // lo que dejaba la franja util comprimida en una fraccion minuscula de la
  // pantalla. Esto es el "zoom"/ampliado que se pidio: cada hora util ocupa
  // mucho mas espacio vertical sin que el usuario tenga que hacer nada.
  slotMinTime: '06:00:00',
  slotMaxTime: '19:00:00',
  slotDuration: '00:15:00',
  slotLabelInterval: '01:00:00',
  // Alto fijo generoso (en vez de 'auto') + expandRows -- asi cada franja de
  // 15 min ocupa espacio real en pantalla en lugar de comprimirse para que
  // quepan las 13 horas del dia en el alto que sea que tenga el contenedor.
  height: 900,
  expandRows: true,
  nowIndicator: true,
  // Default de FullCalendar es 'true' -- dibuja citas simultaneas del MISMO
  // profesional superpuestas con un offset chiquito (pensado para 2 cosas
  // que se cruzan apenas). Con 2+ consultorios reales corriendo en paralelo
  // para el mismo profesional (ver datos importados), eso produce texto
  // literalmente ilegible encimado. 'false' las reparte en columnas propias
  // sin superposicion -- mismo criterio que usa Google Calendar.
  slotEventOverlap: false,
  events: events.value,
  eventTextColor: 'inherit',
  // Clases de Tailwind puestas directamente en el elemento .fc-event (API
  // oficial de FullCalendar para esto) -- asi la tarjeta se ve como una
  // "pastilla" solida con esquinas redondeadas y sombra suave (estilo
  // Google Calendar que pidio el usuario) sin tocar el CSS interno de la
  // libreria ni escribir CSS propio. El borde (color de estado, ver
  // "events" arriba) se deja intacto a proposito -- es la unica señal de
  // estado que queda en esta vista.
  eventClassNames: ['rounded-lg', 'shadow-sm'],
  datesSet: info => {
    // +-1 dia de colchon contra el borde de zona horaria (el rango de
    // FullCalendar viene en hora local del navegador, no en America/Bogota).
    const since = new Date(info.start);
    since.setDate(since.getDate() - 1);
    const until = new Date(info.end);
    until.setDate(until.getDate() + 1);
    fetchRange(since, until);
  },
  dateClick: info => {
    presetStartsAt.value = info.date;
    presetProfessionalId.value = info.resource
      ? Number(info.resource.id)
      : null;
    showFormModal.value = true;
  },
  eventClick: info => {
    openDetailModal(info.event.id);
  },
}));

const closeFormModal = () => {
  showFormModal.value = false;
  presetStartsAt.value = null;
  presetProfessionalId.value = null;
};

onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('calendarioServices/get'),
      store.dispatch('calendarioProfessionals/get'),
      store.dispatch('calendarioPayers/get'),
      store.dispatch('calendarioSpecialties/get'),
    ]);
  } catch (error) {
    useAlert(t('CALENDARIO.CALENDAR.FETCH_ERROR'));
  }
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex flex-wrap items-end gap-3">
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.CALENDAR.FILTERS.SPECIALTY_LABEL')
        }}</label>
        <MultiSelect
          v-model="selectedSpecialties"
          :options="specialtyOptions"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.CALENDAR.FILTERS.PROFESSIONAL_LABEL')
        }}</label>
        <MultiSelect
          v-model="selectedProfessionals"
          :options="professionalOptions"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.CALENDAR.FILTERS.SERVICE_LABEL')
        }}</label>
        <MultiSelect v-model="selectedServices" :options="serviceOptions" />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.CALENDAR.FILTERS.PAYER_LABEL')
        }}</label>
        <MultiSelect v-model="selectedPayers" :options="payerOptions" />
      </div>
    </div>

    <FullCalendar :options="calendarOptions">
      <template #eventContent="arg">
        <div class="flex items-start gap-1 px-1 py-0.5 overflow-hidden w-full">
          <span
            class="mt-1 size-2 shrink-0 rounded-full"
            :style="{ backgroundColor: arg.event.extendedProps.serviceColor }"
          />
          <div class="flex flex-col min-w-0 leading-tight">
            <p class="text-xs font-medium truncate">
              {{ arg.event.extendedProps.contactName }}
            </p>
            <p class="text-[11px] opacity-80 truncate">
              {{ arg.timeText }} · {{ arg.event.extendedProps.serviceName }}
            </p>
          </div>
        </div>
      </template>
    </FullCalendar>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <AppointmentFormModal
        :preset-starts-at="presetStartsAt"
        :preset-professional-id="presetProfessionalId"
        @close="closeFormModal"
        @created="refreshVisibleRange"
      />
    </woot-modal>

    <woot-modal v-model:show="showDetailModal" :on-close="closeDetailModal">
      <AppointmentDetailModal
        v-if="selectedAppointmentId"
        :appointment-id="selectedAppointmentId"
        @close="closeDetailModal"
        @reschedule="openRescheduleModal"
        @cancel="openCancelModal"
        @changed="refreshVisibleRange"
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
        @cancelled="refreshVisibleRange"
      />
    </woot-modal>
  </div>
</template>

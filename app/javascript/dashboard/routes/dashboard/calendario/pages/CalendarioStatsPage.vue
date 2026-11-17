<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import subDays from 'date-fns/subDays';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import CalendarioStatsAPI from 'dashboard/api/calendarioStats';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { formatInstantDateTimeEs } from '../helpers/calendarioDateTime';

const { t } = useI18n();
const router = useRouter();
const store = useStore();
const accountId = useMapGetter('getCurrentAccountId');

const customDateRange = ref([subDays(new Date(), 6), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.LAST_7_DAYS);
const isFetching = ref(false);
const stats = ref(null);

// "Programadas" (default, de siempre): volumen por fecha de la cita. "Creadas"
// (nuevo, para auditoria): volumen por fecha en que se REGISTRO la cita --
// pedido explicito del usuario para poder saber "que dia se crearon mas
// citas" y, ante un reclamo ("yo nunca reserve esto"), ubicar el dia exacto
// de creacion y de ahi saltar a la conversacion donde se origino.
const GROUP_BY_TABS = [
  { key: 'starts_at', label: t('CALENDARIO.STATS.GROUP_BY.SCHEDULED') },
  { key: 'created_at', label: t('CALENDARIO.STATS.GROUP_BY.CREATED') },
];
const groupBy = ref('starts_at');
const isAuditMode = computed(() => groupBy.value === 'created_at');

const createdRangeAppointments = useMapGetter(
  'calendarioAppointments/getCreatedRangeAppointments'
);
const appointmentsUiFlags = useMapGetter('calendarioAppointments/getUIFlags');
const isFetchingList = computed(
  () => appointmentsUiFlags.value.isFetchingByCreatedRange
);

const summary = computed(() => stats.value?.summary || {});
const days = computed(() => stats.value?.days || []);

const summaryCards = computed(() => [
  {
    label: t('CALENDARIO.STATS.AVG_PER_DAY'),
    value: summary.value.avg_per_day ?? 0,
  },
  {
    label: t('CALENDARIO.STATS.ATTENDED_PCT'),
    value: `${summary.value.attended_pct ?? 0}%`,
  },
  {
    label: t('CALENDARIO.STATS.NO_SHOW_PCT'),
    value: `${summary.value.no_show_pct ?? 0}%`,
  },
  {
    label: t('CALENDARIO.STATS.CANCELLED_PCT'),
    value: `${summary.value.cancelled_pct ?? 0}%`,
  },
]);

const collection = computed(() => ({
  labels: days.value.map(day => day.date),
  datasets: [
    {
      label: isAuditMode.value
        ? t('CALENDARIO.STATS.CHART_LABEL_CREATED')
        : t('CALENDARIO.STATS.CHART_LABEL'),
      backgroundColor: '#1f93ff',
      data: days.value.map(day => day.total),
    },
  ],
}));

const chartOptions = {
  scales: {
    y: { beginAtZero: true, ticks: { precision: 0 } },
  },
};

const statusLabel = status =>
  t(`CALENDARIO.APPOINTMENTS.STATUS.${status.toUpperCase()}`);

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

// La lista de auditoria se ordena por fecha de creacion, no por fecha de la
// cita -- lo que el personal quiere ver primero ante un reclamo es "que se
// registro mas reciente", no cuando quedo agendada.
const sortedCreatedRangeAppointments = computed(() =>
  [...createdRangeAppointments.value].sort(
    (a, b) => new Date(b.created_at) - new Date(a.created_at)
  )
);

const fetchStats = async ([since, until]) => {
  isFetching.value = true;
  try {
    const response = await CalendarioStatsAPI.get({
      since: since.toISOString(),
      until: until.toISOString(),
      groupBy: groupBy.value,
    });
    stats.value = response.data;
  } catch (error) {
    useAlert(t('CALENDARIO.STATS.FETCH_ERROR'));
  } finally {
    isFetching.value = false;
  }
};

const fetchCreatedRangeList = async ([since, until]) => {
  if (!isAuditMode.value) return;
  await store.dispatch('calendarioAppointments/getByCreatedRange', {
    createdSince: since.toISOString(),
    createdUntil: until.toISOString(),
  });
};

const refresh = () => {
  fetchStats(customDateRange.value);
  fetchCreatedRangeList(customDateRange.value);
};

const onDateRangeChange = value => {
  const [startDate, endDate, rangeType] = value;
  customDateRange.value = [startDate, endDate];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
  refresh();
};

const onGroupByChanged = tab => {
  groupBy.value = tab.key;
  refresh();
};

refresh();
</script>

<template>
  <div class="flex flex-col gap-4">
    <p class="text-sm text-n-slate-11">
      {{
        isAuditMode
          ? t('CALENDARIO.STATS.DESCRIPTION_CREATED')
          : t('CALENDARIO.STATS.DESCRIPTION')
      }}
    </p>

    <TabBar
      :tabs="GROUP_BY_TABS"
      :initial-active-tab="GROUP_BY_TABS.findIndex(tab => tab.key === groupBy)"
      @tab-changed="onGroupByChanged"
    />

    <WootDatePicker
      v-model:date-range="customDateRange"
      v-model:range-type="selectedDateRange"
      @date-range-changed="onDateRangeChange"
    />

    <div v-if="isFetching" class="flex items-center justify-center py-8">
      <Spinner />
    </div>
    <template v-else>
      <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
        <div
          v-for="card in summaryCards"
          :key="card.label"
          class="flex flex-col gap-1 rounded-xl border border-n-weak p-4"
        >
          <span class="text-xs text-n-slate-11">{{ card.label }}</span>
          <span class="text-2xl font-semibold text-n-slate-12">{{
            card.value
          }}</span>
        </div>
      </div>

      <div v-if="days.length" class="h-72 p-4 border border-n-weak rounded-xl">
        <BarChart :collection="collection" :chart-options="chartOptions" />
      </div>
      <p v-else class="text-sm text-n-slate-10">
        {{ t('CALENDARIO.STATS.EMPTY') }}
      </p>

      <!-- Drill-down de auditoria: solo en modo "Creadas" -- el chart ya
      responde "que dia se crearon mas citas", esta lista responde "cuales
      fueron, de quien, y como llego hasta la conversacion donde se
      origino". -->
      <div v-if="isAuditMode" class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">{{
          t('CALENDARIO.STATS.CREATED_LIST_TITLE')
        }}</span>
        <div
          v-if="isFetchingList"
          class="flex items-center justify-center py-8"
        >
          <Spinner />
        </div>
        <p
          v-else-if="!sortedCreatedRangeAppointments.length"
          class="text-sm text-n-slate-10 text-center py-8"
        >
          {{ t('CALENDARIO.STATS.CREATED_LIST_EMPTY') }}
        </p>
        <div
          v-else
          class="flex flex-col divide-y divide-n-weak rounded-xl border border-n-weak p-3"
        >
          <div
            v-for="appointment in sortedCreatedRangeAppointments"
            :key="appointment.id"
            class="flex flex-wrap items-center justify-between gap-2 py-2"
          >
            <div class="flex flex-wrap items-center gap-x-2 gap-y-0.5 min-w-0">
              <span class="text-xs text-n-slate-10 w-36 shrink-0">{{
                formatInstantDateTimeEs(appointment.created_at)
              }}</span>
              <router-link
                :to="contactUrl(appointment)"
                class="text-sm hover:underline text-n-blue-text truncate"
              >
                {{ appointment.contact_name }}
              </router-link>
              <span class="text-xs text-n-slate-10 truncate">{{
                appointment.service_name
              }}</span>
              <span class="text-xs text-n-slate-10 truncate">{{
                appointment.professional_name
              }}</span>
              <span class="text-xs text-n-slate-10 truncate">
                {{
                  t('CALENDARIO.STATS.SCHEDULED_FOR', {
                    when: formatInstantDateTimeEs(appointment.starts_at),
                  })
                }}
              </span>
              <span
                v-if="appointment.created_by_name"
                class="text-xs text-n-slate-10 truncate"
              >
                {{
                  t('CALENDARIO.STATS.CREATED_BY', {
                    name: appointment.created_by_name,
                  })
                }}
              </span>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <span class="text-xs text-n-slate-11">{{
                statusLabel(appointment.status)
              }}</span>
              <button
                v-if="appointment.conversation_id"
                type="button"
                class="i-lucide-message-circle size-4 text-n-slate-10 hover:text-n-blue-text"
                @click="openConversation(appointment)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted, ref, h } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import AuditoriaReportConversationsDrawer from './components/AuditoriaReportConversationsDrawer.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import Table from 'dashboard/components/table/Table.vue';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
  getSortedRowModel,
} from '@tanstack/vue-table';

const { t } = useI18n();
const store = useStore();

const from = ref(0);
const to = ref(0);
const selectedInboxId = ref('');
const sameDayOnly = ref(false);

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(
  () => uiFlags.value.isFetchingAuditoriaAdvisorSummaryReports ?? false
);

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');
const reportMetrics = useMapGetter(
  'summaryReports/getAuditoriaAdvisorSummaryReports'
);
const reportTotals = useMapGetter(
  'summaryReports/getAuditoriaAdvisorSummaryTotals'
);

const getMetrics = id =>
  reportMetrics.value.find(metrics => metrics.id === Number(id)) || {};

const renderAvgTime = value => (value ? formatTime(value) : '--');
const renderCount = value => (value ? value.toLocaleString() : '--');

const columnHelper = createColumnHelper();
// Las columnas numericas ordenan sobre el valor crudo (getValue) y solo
// formatean para mostrar -- si se ordenara sobre el texto ya formateado
// ("1h 30m" vs "45m"), el orden alfabetico de strings no respetaria la
// duracion real.
const countCellRender = cellProps =>
  h(
    'span',
    { class: cellProps.getValue() ? '' : 'text-n-slate-12' },
    renderCount(cellProps.getValue())
  );
const avgTimeCellRender = cellProps =>
  h(
    'span',
    { class: cellProps.getValue() ? '' : 'text-n-slate-12' },
    renderAvgTime(cellProps.getValue())
  );

const selectedAdvisor = ref(null);
const isDrawerOpen = computed(() => !!selectedAdvisor.value);
const openAdvisorDrawer = row => {
  selectedAdvisor.value = { id: row.id, name: row.name };
};
const closeAdvisorDrawer = () => {
  selectedAdvisor.value = null;
};

// Computed (no snapshot al momento del click) para que si el usuario abre
// el drawer y luego cambia el toggle "mismo dia" en la pagina de atras, el
// desglose dentro del drawer ya abierto se actualice solo.
const selectedAdvisorBreakdown = computed(() => {
  if (!selectedAdvisor.value) return [];
  return getMetrics(selectedAdvisor.value.id).responseBreakdown || [];
});

// Wrapper local (no la referencia desnuda del metodo) -- useReportDrilldown
// invoca fetcher(...) como funcion suelta, y SummaryReportsAPI.method sin
// el objeto delante perderia el `this.url` interno de ApiClient.
const fetchAdvisorConversations = params =>
  SummaryReportsAPI.getAuditoriaAdvisorConversations(params);

const columns = computed(() => [
  columnHelper.accessor('name', {
    header: t('SUMMARY_REPORTS.AGENT'),
    width: 300,
    cell: cellProps =>
      h(
        'button',
        {
          type: 'button',
          class: 'text-n-blue-text hover:underline',
          onClick: () => openAdvisorDrawer(cellProps.row.original),
        },
        cellProps.getValue()
      ),
  }),
  columnHelper.accessor('conversationsCount', {
    header: t('SUMMARY_REPORTS.CONVERSATIONS'),
    width: 200,
    cell: countCellRender,
  }),
  columnHelper.accessor('avgResponseTime', {
    header: t('SUMMARY_REPORTS.AVG_RESPONSE_TIME'),
    width: 200,
    cell: avgTimeCellRender,
  }),
]);

// agents/getAgents trae todos los account_users (incluye administradores,
// como Chatwoot ya hace en su propio reporte nativo de agentes) - aqui
// filtramos solo a quien de verdad atiende WhatsApp como asesor.
const advisorRows = computed(() =>
  agents.value
    .filter(agent => agent.role === 'agent')
    .map(agent => {
      const { conversationsCount, avgResponseTimeSeconds } = getMetrics(
        agent.id
      );
      return {
        id: agent.id,
        name: agent.name,
        conversationsCount: conversationsCount || 0,
        avgResponseTime: avgResponseTimeSeconds ?? null,
      };
    })
);

// Al filtrar por una bandeja puntual, la mayoria de asesores no trabajan
// ahi -- se quitan del todo en vez de mostrarlos en "--" (ver backend).
const tableData = computed(() => {
  if (!selectedInboxId.value) return advisorRows.value;

  return advisorRows.value.filter(row => row.conversationsCount > 0);
});

const fetchReportsWithRetry = async () => {
  const params = {
    since: from.value,
    until: to.value,
    inboxId: selectedInboxId.value || undefined,
    sameDayOnly: sameDayOnly.value,
  };
  try {
    await store.dispatch(
      'summaryReports/fetchAuditoriaAdvisorSummaryReports',
      params
    );
  } catch {
    try {
      await store.dispatch(
        'summaryReports/fetchAuditoriaAdvisorSummaryReports',
        params
      );
    } catch {
      useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
    }
  }
};

const fetchAllData = () => {
  store.dispatch('agents/get');
  fetchReportsWithRetry();
};

onMounted(() => fetchAllData());

const onFilterChange = updatedFilter => {
  from.value = updatedFilter.from;
  to.value = updatedFilter.to;
  fetchAllData();
};

const onInboxChange = () => fetchAllData();
const onSameDayToggle = () => fetchAllData();

const totalsSummary = computed(() => {
  if (!reportTotals.value) return '';

  return t('AUDITORIA_ADVISOR_REPORTS.TOTALS_SUMMARY', {
    conversations: renderCount(reportTotals.value.conversationsCount),
    avgResponseTime: renderAvgTime(reportTotals.value.avgResponseTimeSeconds),
  });
});

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  get columns() {
    return columns.value;
  },
  enableSorting: true,
  getCoreRowModel: getCoreRowModel(),
  getSortedRowModel: getSortedRowModel(),
  initialState: {
    sorting: [{ id: 'name', desc: false }],
  },
});
</script>

<template>
  <ReportHeader
    :header-title="$t('AUDITORIA_ADVISOR_REPORTS.HEADER')"
    :header-description="$t('AUDITORIA_ADVISOR_REPORTS.DESCRIPTION')"
  />

  <div class="flex flex-col justify-between gap-3 md:flex-row">
    <OverviewReportFilters
      :disabled="isLoading"
      @filter-change="onFilterChange"
    />
    <div
      class="flex flex-wrap items-center gap-4"
      :class="{ 'pointer-events-none opacity-50': isLoading }"
    >
      <div class="flex items-center gap-2">
        <label for="auditoria-inbox-filter" class="text-sm whitespace-nowrap">
          {{ $t('AUDITORIA_ADVISOR_REPORTS.INBOX_FILTER_LABEL') }}
        </label>
        <select
          id="auditoria-inbox-filter"
          v-model="selectedInboxId"
          class="reset-base !mb-0 !w-auto"
          :disabled="isLoading"
          @change="onInboxChange"
        >
          <option value="">
            {{ $t('AUDITORIA_ADVISOR_REPORTS.INBOX_FILTER_ALL') }}
          </option>
          <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
            {{ inbox.name }}
          </option>
        </select>
      </div>
      <div class="flex items-center gap-2">
        <label
          for="auditoria-same-day-toggle"
          class="text-sm whitespace-nowrap"
        >
          {{ $t('AUDITORIA_ADVISOR_REPORTS.SAME_DAY_TOGGLE_LABEL') }}
        </label>
        <ToggleSwitch
          id="auditoria-same-day-toggle"
          v-model="sameDayOnly"
          @change="onSameDayToggle"
        />
      </div>
    </div>
  </div>

  <div
    class="relative flex-1 overflow-auto px-2 py-2 mt-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <Table :table="table" />
    <Transition
      enter-active-class="transition-opacity duration-300 ease-out"
      leave-active-class="transition-opacity duration-200 ease-in"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="isLoading"
        class="absolute inset-0 flex justify-center pt-[12.5rem] bg-n-solid-1/70 rounded-xl pointer-events-none"
      >
        <Spinner :size="32" class="text-n-brand" />
      </div>
    </Transition>
  </div>

  <p v-if="totalsSummary" class="text-sm text-n-slate-11 mt-2 text-right">
    {{ totalsSummary }}
  </p>

  <AuditoriaReportConversationsDrawer
    :open="isDrawerOpen"
    :title="selectedAdvisor?.name"
    :description="
      t('AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.DESCRIPTION')
    "
    :empty-text="t('AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.EMPTY')"
    :error-text="t('AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.ERROR')"
    :response-breakdown="selectedAdvisorBreakdown"
    show-breakdown
    :filter-params="{
      userId: selectedAdvisor?.id,
      since: from,
      until: to,
      inboxId: selectedInboxId,
    }"
    :fetcher="fetchAdvisorConversations"
    @close="closeAdvisorDrawer"
  />
</template>

<script setup>
import { computed, onMounted, ref, h } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Table from 'dashboard/components/table/Table.vue';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';

const { t } = useI18n();
const store = useStore();

const from = ref(0);
const to = ref(0);
const selectedInboxId = ref('');

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(
  () => uiFlags.value.isFetchingAuditoriaAdvisorSummaryReports ?? false
);

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');
const reportMetrics = useMapGetter(
  'summaryReports/getAuditoriaAdvisorSummaryReports'
);

const getMetrics = id =>
  reportMetrics.value.find(metrics => metrics.id === Number(id)) || {};

const renderAvgTime = value => (value ? formatTime(value) : '--');
const renderCount = value => (value ? value.toLocaleString() : '--');

const columnHelper = createColumnHelper();
const defaulSpanRender = cellProps =>
  h(
    'span',
    { class: cellProps.getValue() ? '' : 'text-n-slate-12' },
    cellProps.getValue()
  );

const columns = computed(() => [
  columnHelper.accessor('name', {
    header: t('SUMMARY_REPORTS.AGENT'),
    width: 300,
    cell: defaulSpanRender,
  }),
  columnHelper.accessor('conversationsCount', {
    header: t('SUMMARY_REPORTS.CONVERSATIONS'),
    width: 200,
    cell: defaulSpanRender,
  }),
  columnHelper.accessor('avgResponseTime', {
    header: t('SUMMARY_REPORTS.AVG_RESPONSE_TIME'),
    width: 200,
    cell: defaulSpanRender,
  }),
]);

// agents/getAgents trae todos los account_users (incluye administradores,
// como Chatwoot ya hace en su propio reporte nativo de agentes) - aqui
// filtramos solo a quien de verdad atiende WhatsApp como asesor.
const tableData = computed(() =>
  agents.value
    .filter(agent => agent.role === 'agent')
    .map(agent => {
      const { conversationsCount, avgResponseTimeSeconds } = getMetrics(
        agent.id
      );
      return {
        id: agent.id,
        name: agent.name,
        conversationsCount: renderCount(conversationsCount),
        avgResponseTime: renderAvgTime(avgResponseTimeSeconds),
      };
    })
);

const fetchReportsWithRetry = async () => {
  const params = {
    since: from.value,
    until: to.value,
    inboxId: selectedInboxId.value || undefined,
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

const table = useVueTable({
  get data() {
    return tableData.value;
  },
  get columns() {
    return columns.value;
  },
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
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
</template>

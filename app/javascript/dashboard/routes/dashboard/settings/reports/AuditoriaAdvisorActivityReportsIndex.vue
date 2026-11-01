<script setup>
import { computed, onMounted, ref, h } from 'vue';
import { useI18n } from 'vue-i18n';
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
  getSortedRowModel,
} from '@tanstack/vue-table';

const { t } = useI18n();
const store = useStore();

const from = ref(0);
const to = ref(0);
const selectedInboxId = ref('');
// 'advisor' | 'team' -- ambos leen del mismo payload ya cargado, sin
// refetch al cambiar (ver advisors/teams abajo).
const viewMode = ref('advisor');

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(
  () => uiFlags.value.isFetchingAuditoriaAdvisorActivity ?? false
);

const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');
const inboxes = useMapGetter('inboxes/getInboxes');
const advisorMetrics = useMapGetter(
  'summaryReports/getAuditoriaAdvisorActivityAdvisors'
);
const teamMetrics = useMapGetter(
  'summaryReports/getAuditoriaAdvisorActivityTeams'
);

const renderCount = value => (value ? value.toLocaleString() : '--');
const renderAvg = value => (value ? value.toLocaleString() : '--');

// agents/getAgents trae todos los account_users (incluye administradores)
// -- igual que el reporte de Asesores en vivo, aqui solo cuenta quien de
// verdad atiende WhatsApp.
const advisorRows = computed(() => {
  const metricsById = new Map(advisorMetrics.value.map(row => [row.id, row]));
  return agents.value
    .filter(agent => agent.role === 'agent')
    .map(agent => ({ name: agent.name, ...(metricsById.get(agent.id) || {}) }));
});

const teamRows = computed(() => {
  const metricsById = new Map(teamMetrics.value.map(row => [row.id, row]));
  return teams.value.map(team => ({
    name: team.name,
    ...(metricsById.get(team.id) || {}),
  }));
});

const tableData = computed(() =>
  viewMode.value === 'team' ? teamRows.value : advisorRows.value
);

const columnHelper = createColumnHelper();
const countCellRender = cellProps =>
  h('span', {}, renderCount(cellProps.getValue()));
const avgCellRender = cellProps =>
  h('span', {}, renderAvg(cellProps.getValue()));

const columns = computed(() => [
  columnHelper.accessor('name', {
    header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.NAME'),
    width: 220,
  }),
  columnHelper.accessor('conversationsCount', {
    header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.CONVERSATIONS'),
    width: 140,
    cell: countCellRender,
  }),
  columnHelper.group({
    id: 'messages',
    header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.MESSAGES_GROUP'),
    columns: [
      columnHelper.accessor('outgoingCount', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.OUTGOING'),
        width: 110,
        cell: countCellRender,
      }),
      columnHelper.accessor('avgOutgoingPerConversation', {
        header: t(
          'AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.AVG_PER_CONVERSATION'
        ),
        width: 110,
        cell: avgCellRender,
      }),
      columnHelper.accessor('incomingCount', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.INCOMING'),
        width: 110,
        cell: countCellRender,
      }),
      columnHelper.accessor('avgIncomingPerConversation', {
        header: t(
          'AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.AVG_PER_CONVERSATION'
        ),
        width: 110,
        cell: avgCellRender,
      }),
    ],
  }),
  columnHelper.group({
    id: 'text',
    header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.TEXT_GROUP'),
    columns: [
      columnHelper.accessor('charactersWritten', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.CHARACTERS'),
        width: 110,
        cell: countCellRender,
      }),
      columnHelper.accessor('wordsWritten', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.WORDS'),
        width: 110,
        cell: countCellRender,
      }),
    ],
  }),
  columnHelper.group({
    id: 'audio',
    header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.AUDIO_GROUP'),
    columns: [
      columnHelper.accessor('audioIncoming', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.INCOMING'),
        width: 100,
        cell: countCellRender,
      }),
      columnHelper.accessor('audioOutgoing', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.OUTGOING'),
        width: 100,
        cell: countCellRender,
      }),
    ],
  }),
  columnHelper.group({
    id: 'image',
    header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.PHOTO_GROUP'),
    columns: [
      columnHelper.accessor('imageIncoming', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.INCOMING'),
        width: 100,
        cell: countCellRender,
      }),
      columnHelper.accessor('imageOutgoing', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.OUTGOING'),
        width: 100,
        cell: countCellRender,
      }),
    ],
  }),
  columnHelper.group({
    id: 'video',
    header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.VIDEO_GROUP'),
    columns: [
      columnHelper.accessor('videoIncoming', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.INCOMING'),
        width: 100,
        cell: countCellRender,
      }),
      columnHelper.accessor('videoOutgoing', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.OUTGOING'),
        width: 100,
        cell: countCellRender,
      }),
    ],
  }),
  columnHelper.group({
    id: 'calls',
    header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.CALLS_GROUP'),
    columns: [
      columnHelper.accessor('callsIncoming', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.INCOMING'),
        width: 100,
        cell: countCellRender,
      }),
      columnHelper.accessor('callsOutgoing', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.OUTGOING'),
        width: 100,
        cell: countCellRender,
      }),
      columnHelper.accessor('callsMissed', {
        header: t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.COLUMNS.MISSED'),
        width: 100,
        cell: countCellRender,
      }),
    ],
  }),
]);

const fetchReportsWithRetry = async () => {
  const params = {
    since: from.value,
    until: to.value,
    inboxId: selectedInboxId.value || undefined,
  };
  try {
    await store.dispatch(
      'summaryReports/fetchAuditoriaAdvisorActivity',
      params
    );
  } catch {
    try {
      await store.dispatch(
        'summaryReports/fetchAuditoriaAdvisorActivity',
        params
      );
    } catch {
      useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
    }
  }
};

const fetchAllData = () => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  fetchReportsWithRetry();
};

onMounted(fetchAllData);

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
    :header-title="$t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.HEADER')"
    :header-description="$t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.DESCRIPTION')"
  />

  <div class="flex flex-col justify-between gap-3 md:flex-row">
    <OverviewReportFilters
      :disabled="isLoading"
      hide-business-hours
      @filter-change="onFilterChange"
    />
    <div
      class="flex flex-wrap items-center gap-4"
      :class="{ 'pointer-events-none opacity-50': isLoading }"
    >
      <div class="flex items-center gap-2">
        <label
          for="auditoria-activity-inbox-filter"
          class="text-sm whitespace-nowrap"
        >
          {{ $t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.INBOX_FILTER_LABEL') }}
        </label>
        <select
          id="auditoria-activity-inbox-filter"
          v-model="selectedInboxId"
          class="reset-base !mb-0 !w-auto"
          :disabled="isLoading"
          @change="onInboxChange"
        >
          <option value="">
            {{ $t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.INBOX_FILTER_ALL') }}
          </option>
          <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
            {{ inbox.name }}
          </option>
        </select>
      </div>
      <div class="flex items-center gap-1 rounded-lg bg-n-alpha-2 p-0.5">
        <button
          type="button"
          class="rounded-md px-3 py-1 text-sm"
          :class="
            viewMode === 'advisor'
              ? 'bg-n-solid-2 shadow text-n-slate-12'
              : 'text-n-slate-11'
          "
          @click="viewMode = 'advisor'"
        >
          {{ $t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.VIEW_ADVISOR') }}
        </button>
        <button
          type="button"
          class="rounded-md px-3 py-1 text-sm"
          :class="
            viewMode === 'team'
              ? 'bg-n-solid-2 shadow text-n-slate-12'
              : 'text-n-slate-11'
          "
          @click="viewMode = 'team'"
        >
          {{ $t('AUDITORIA_ADVISOR_ACTIVITY_REPORTS.VIEW_TEAM') }}
        </button>
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
</template>

<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import AuditoriaReportConversationsDrawer from './components/AuditoriaReportConversationsDrawer.vue';
import AuditoriaSentimentChart from './components/AuditoriaSentimentChart.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SummaryReportsAPI from 'dashboard/api/summaryReports';

const { t } = useI18n();
const store = useStore();

const from = ref(0);
const to = ref(0);
const selectedInboxId = ref('');
const selectedUserId = ref('');
const selectedTeamId = ref('');

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(
  () => uiFlags.value.isFetchingAuditoriaSentimentTimeseries ?? false
);

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');
const timeseries = useMapGetter(
  'summaryReports/getAuditoriaSentimentTimeseries'
);
const timeseriesBucket = useMapGetter(
  'summaryReports/getAuditoriaSentimentTimeseriesBucket'
);

// auditoria_source_user_id puede resolver a cualquier account_user que haya
// respondido, no solo rol "agent" -- mismo criterio que el resumen diario
// por asesor, para no esconder casos de administradores que tambien
// atendieron conversaciones.
const advisorOptions = computed(() =>
  [...agents.value].sort((a, b) => a.name.localeCompare(b.name))
);

const fetchTimeseries = async () => {
  const params = {
    since: from.value,
    until: to.value,
    inboxId: selectedInboxId.value || undefined,
    userId: selectedUserId.value || undefined,
    teamId: selectedTeamId.value || undefined,
  };
  try {
    await store.dispatch(
      'summaryReports/fetchAuditoriaSentimentTimeseries',
      params
    );
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  }
};

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  fetchTimeseries();
});

const onFilterChange = updatedFilter => {
  from.value = updatedFilter.from;
  to.value = updatedFilter.to;
  fetchTimeseries();
};

const onInboxChange = () => fetchTimeseries();
const onAdvisorChange = () => fetchTimeseries();
const onTeamChange = () => fetchTimeseries();

// Clic en un punto de la grafica -- abre el drawer con las conversaciones
// de CUALQUIER sentimiento en ese dia/semana/mes (cada tarjeta muestra su
// propio badge de sentimiento, ver ReportDrilldownCard), acotadas a los
// mismos filtros de asesor/equipo/bandeja ya aplicados arriba.
const selectedBucket = ref(null);
const isDrawerOpen = computed(() => !!selectedBucket.value);
const openBucketDrawer = ({ since, until }) => {
  selectedBucket.value = { since, until };
};
const closeBucketDrawer = () => {
  selectedBucket.value = null;
};
const fetchBucketConversations = params =>
  SummaryReportsAPI.getAuditoriaSentimentConversations(params);

const bucketDrawerLabel = computed(() => {
  if (!selectedBucket.value) return '';

  const { since, until } = selectedBucket.value;
  const start = format(fromUnixTime(since), 'd MMM yyyy');
  const end = format(fromUnixTime(until), 'd MMM yyyy');
  return start === end ? start : `${start} - ${end}`;
});

const drawerFilterParams = computed(() => {
  if (!selectedBucket.value) return {};

  return {
    since: selectedBucket.value.since,
    until: selectedBucket.value.until,
    inboxId: selectedInboxId.value || undefined,
    userId: selectedUserId.value || undefined,
    teamId: selectedTeamId.value || undefined,
  };
});
</script>

<template>
  <ReportHeader
    :header-title="$t('AUDITORIA_SENTIMENT_REPORTS.HEADER')"
    :header-description="$t('AUDITORIA_SENTIMENT_REPORTS.DESCRIPTION')"
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
          for="auditoria-sentiment-advisor-filter"
          class="text-sm whitespace-nowrap"
        >
          {{ $t('AUDITORIA_SENTIMENT_REPORTS.ADVISOR_FILTER_LABEL') }}
        </label>
        <select
          id="auditoria-sentiment-advisor-filter"
          v-model="selectedUserId"
          class="reset-base !mb-0 !w-auto"
          :disabled="isLoading"
          @change="onAdvisorChange"
        >
          <option value="">
            {{ $t('AUDITORIA_SENTIMENT_REPORTS.ADVISOR_FILTER_ALL') }}
          </option>
          <option
            v-for="advisor in advisorOptions"
            :key="advisor.id"
            :value="advisor.id"
          >
            {{ advisor.name }}
          </option>
        </select>
      </div>
      <div class="flex items-center gap-2">
        <label
          for="auditoria-sentiment-team-filter"
          class="text-sm whitespace-nowrap"
        >
          {{ $t('AUDITORIA_SENTIMENT_REPORTS.TEAM_FILTER_LABEL') }}
        </label>
        <select
          id="auditoria-sentiment-team-filter"
          v-model="selectedTeamId"
          class="reset-base !mb-0 !w-auto"
          :disabled="isLoading"
          @change="onTeamChange"
        >
          <option value="">
            {{ $t('AUDITORIA_SENTIMENT_REPORTS.TEAM_FILTER_ALL') }}
          </option>
          <option v-for="team in teams" :key="team.id" :value="team.id">
            {{ team.name }}
          </option>
        </select>
      </div>
      <div class="flex items-center gap-2">
        <label
          for="auditoria-sentiment-inbox-filter"
          class="text-sm whitespace-nowrap"
        >
          {{ $t('AUDITORIA_SENTIMENT_REPORTS.INBOX_FILTER_LABEL') }}
        </label>
        <select
          id="auditoria-sentiment-inbox-filter"
          v-model="selectedInboxId"
          class="reset-base !mb-0 !w-auto"
          :disabled="isLoading"
          @change="onInboxChange"
        >
          <option value="">
            {{ $t('AUDITORIA_SENTIMENT_REPORTS.INBOX_FILTER_ALL') }}
          </option>
          <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
            {{ inbox.name }}
          </option>
        </select>
      </div>
    </div>
  </div>

  <div
    class="relative mt-5 rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
  >
    <AuditoriaSentimentChart
      :series="timeseries"
      :since="from"
      :until="to"
      :bucket="timeseriesBucket"
      @select-bucket="openBucketDrawer"
    />
    <div
      v-if="isLoading"
      class="absolute inset-0 flex items-center justify-center rounded-xl bg-n-solid-1/70"
    >
      <Spinner :size="32" class="text-n-brand" />
    </div>
  </div>

  <AuditoriaReportConversationsDrawer
    :open="isDrawerOpen"
    :title="bucketDrawerLabel"
    :description="
      $t('AUDITORIA_SENTIMENT_REPORTS.CONVERSATIONS_DRAWER.DESCRIPTION')
    "
    :empty-text="$t('AUDITORIA_SENTIMENT_REPORTS.CONVERSATIONS_DRAWER.EMPTY')"
    :error-text="$t('AUDITORIA_SENTIMENT_REPORTS.CONVERSATIONS_DRAWER.ERROR')"
    :filter-params="drawerFilterParams"
    :fetcher="fetchBucketConversations"
    @close="closeBucketDrawer"
  />
</template>

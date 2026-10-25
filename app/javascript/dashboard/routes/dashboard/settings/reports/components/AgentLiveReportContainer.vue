<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import AgentTable from './overview/AgentTable.vue';
import MetricCard from './overview/MetricCard.vue';
import OverviewReportFilters from './OverviewReportFilters.vue';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useLiveRefresh } from 'dashboard/composables/useLiveRefresh';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import subDays from 'date-fns/subDays';

const { t } = useI18n();
const store = useStore();

const uiFlags = useMapGetter('getOverviewUIFlags');
const agentConversationMetric = useMapGetter('getAgentConversationMetric');
const agents = useMapGetter('agents/getAgents');
const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);
const isAuditoriaAccount = computed(() =>
  isFeatureEnabledonAccount.value(accountId.value, 'auditoria')
);

const fetchData = () => store.dispatch('fetchAgentConversationMetric');

const { startRefetching } = useLiveRefresh(fetchData);

// "Desatendido" no aplica a cuentas de Auditoria (no lo tabulan) -- en su
// lugar se muestra el tiempo de respuesta promedio por asesor, el mismo
// calculo ya expuesto por el reporte de Asesores (Auditoria::
// AdvisorSummaryBuilder#totals/response_breakdown), que SI necesita un
// rango de fechas -- a diferencia del resto de esta tarjeta, que es en
// vivo sin rango.
const since = ref(getUnixStartOfDay(subDays(new Date(), 6)));
const until = ref(getUnixEndOfDay(new Date()));
const isFetchingResponseTime = ref(false);
const responseTimeByAgentId = ref({});

const fetchResponseTimeByAgent = async () => {
  isFetchingResponseTime.value = true;
  try {
    const { data } = await SummaryReportsAPI.getAuditoriaAdvisorReports({
      since: since.value,
      until: until.value,
    });
    responseTimeByAgentId.value = Object.fromEntries(
      data.advisors.map(advisor => [
        advisor.id,
        advisor.avg_response_time_seconds,
      ])
    );
  } catch (error) {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  } finally {
    isFetchingResponseTime.value = false;
  }
};

const onFilterChange = updatedFilter => {
  since.value = updatedFilter.from;
  until.value = updatedFilter.to;
  fetchResponseTimeByAgent();
};

onMounted(() => {
  store.dispatch('agents/get');
  fetchData();
  startRefetching();
  if (isAuditoriaAccount.value) fetchResponseTimeByAgent();
});
</script>

<template>
  <div class="flex flex-row flex-wrap max-w-full">
    <MetricCard :header="$t('OVERVIEW_REPORTS.AGENT_CONVERSATIONS.HEADER')">
      <template v-if="isAuditoriaAccount" #control>
        <OverviewReportFilters
          hide-business-hours
          @filter-change="onFilterChange"
        />
      </template>
      <AgentTable
        :agents="agents"
        :agent-metrics="agentConversationMetric"
        :is-loading="uiFlags.isFetchingAgentConversationMetric"
        :is-auditoria-account="isAuditoriaAccount"
        :response-time-by-agent-id="responseTimeByAgentId"
      />
    </MetricCard>
  </div>
</template>

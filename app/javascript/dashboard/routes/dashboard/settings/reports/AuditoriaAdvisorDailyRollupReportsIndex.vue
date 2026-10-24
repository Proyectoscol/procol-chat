<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, parseISO } from 'date-fns';
import { es } from 'date-fns/locale';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import AuditoriaReportConversationsDrawer from './components/AuditoriaReportConversationsDrawer.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SummaryReportsAPI from 'dashboard/api/summaryReports';

const { t, locale } = useI18n();
const store = useStore();

const from = ref(0);
const to = ref(0);
const selectedInboxId = ref('');
const selectedUserId = ref('');
const selectedPositiveTag = ref('');
const selectedNegativeTag = ref('');
const sortBy = ref('date');

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(
  () => uiFlags.value.isFetchingAuditoriaAdvisorDailyRollup ?? false
);

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');
const summaries = useMapGetter(
  'summaryReports/getAuditoriaAdvisorDailyRollupSummaries'
);

// auditoria_source_user_id puede resolver a cualquier account_user que haya
// respondido (no solo rol "agent", a diferencia del reporte de Advisors en
// vivo) -- se incluyen todos para no esconder resumenes de administradores
// que tambien atendieron conversaciones.
const advisorOptions = computed(() =>
  [...agents.value].sort((a, b) => a.name.localeCompare(b.name))
);

const agentNameById = computed(() =>
  Object.fromEntries(agents.value.map(agent => [agent.id, agent.name]))
);
const advisorName = userId => agentNameById.value[userId] || `#${userId}`;

const agentThumbnailById = computed(() =>
  Object.fromEntries(agents.value.map(agent => [agent.id, agent.thumbnail]))
);
const advisorThumbnail = userId => agentThumbnailById.value[userId] || '';

const dateLocale = computed(() => (locale.value === 'es' ? es : undefined));
const formatSummaryDate = isoDate =>
  format(parseISO(isoDate), 'd MMM yyyy', { locale: dateLocale.value });
const formatGeneratedAt = isoDatetime =>
  isoDatetime
    ? format(parseISO(isoDatetime), 'd MMM yyyy, HH:mm', {
        locale: dateLocale.value,
      })
    : '';

const categoryChips = row =>
  Object.entries(row.categoryCounts || {}).map(([title, count]) => ({
    title,
    count,
  }));

const negativeDetailFor = (row, tag) =>
  (row.feedbackTagsNegativeDetail || []).find(detail => detail.tag === tag) || {
    tag,
    reason: '',
    conversationIds: [],
  };

// Conjunto de etiquetas distintas ya cargadas (sin paginar) -- el filtro es
// del lado del cliente, no hay endpoint nuevo que soporte filtrar por tag.
const availableTagsFrom = field => {
  const tags = new Set();
  summaries.value.forEach(row =>
    (row[field] || []).forEach(tag => tags.add(tag))
  );
  return [...tags].sort((a, b) => a.localeCompare(b));
};
const availablePositiveTags = computed(() =>
  availableTagsFrom('feedbackTagsPositive')
);
const availableNegativeTags = computed(() =>
  availableTagsFrom('feedbackTagsNegative')
);

const filteredSummaries = computed(() =>
  summaries.value.filter(row => {
    if (
      selectedPositiveTag.value &&
      !(row.feedbackTagsPositive || []).includes(selectedPositiveTag.value)
    ) {
      return false;
    }
    if (
      selectedNegativeTag.value &&
      !(row.feedbackTagsNegative || []).includes(selectedNegativeTag.value)
    ) {
      return false;
    }
    return true;
  })
);

// Orden alfabetico es puramente de presentacion sobre los datos ya
// cargados -- el backend sigue devolviendo summary_date desc, que es el
// orden que se usa por defecto.
const displayedSummaries = computed(() => {
  if (sortBy.value !== 'name') return filteredSummaries.value;

  return [...filteredSummaries.value].sort((a, b) =>
    advisorName(a.userId).localeCompare(advisorName(b.userId))
  );
});

const selectedSummary = ref(null);
const isDrawerOpen = computed(() => !!selectedSummary.value);
const openConversationsDrawer = row => {
  selectedSummary.value = row;
};
const closeConversationsDrawer = () => {
  selectedSummary.value = null;
};

// Wrapper local (no la referencia desnuda del metodo) -- useReportDrilldown
// invoca fetcher(...) como funcion suelta, y SummaryReportsAPI.method sin
// el objeto delante perderia el `this.url` interno de ApiClient.
const fetchDayConversations = params =>
  SummaryReportsAPI.getAuditoriaAdvisorConversations(params);

// UTC exacto (no startOfDay/endOfDay del navegador) para calzar con como
// el backend calcula summary_date.all_day -- usar el dia local del
// navegador correria el riesgo de un desfase de huso horario en la
// frontera del dia.
const dayBoundsUtc = isoDate => {
  const [year, month, day] = isoDate.split('-').map(Number);
  const since = Date.UTC(year, month - 1, day) / 1000;
  return { since, until: since + 86400 - 1 };
};

const drawerFilterParams = computed(() => {
  if (!selectedSummary.value) return {};

  const { since, until } = dayBoundsUtc(selectedSummary.value.summaryDate);
  return {
    userId: selectedSummary.value.userId,
    since,
    until,
    inboxId: selectedInboxId.value || undefined,
  };
});

// Cita de una etiqueta negativa puntual -- drawer separado del de "todas
// las conversaciones del dia" (arriba), filtrado a los conversation_id
// exactos que la IA citó para esa etiqueta (ver
// Auditoria::AdvisorDailyRollupService#feedback_tags_negative_detail).
const selectedCitation = ref(null);
const isCitationDrawerOpen = computed(() => !!selectedCitation.value);
const openCitationDrawer = detail => {
  if (!detail.conversationIds?.length) return;
  selectedCitation.value = detail;
};
const closeCitationDrawer = () => {
  selectedCitation.value = null;
};
const fetchCitationConversations = params =>
  SummaryReportsAPI.getAuditoriaAdvisorConversations(params);
const citationDrawerFilterParams = computed(() => ({
  conversationIds: selectedCitation.value?.conversationIds || [],
}));

const fetchReportsWithRetry = async () => {
  const params = {
    since: from.value,
    until: to.value,
    inboxId: selectedInboxId.value || undefined,
    userId: selectedUserId.value || undefined,
  };
  try {
    await store.dispatch(
      'summaryReports/fetchAuditoriaAdvisorDailyRollup',
      params
    );
  } catch {
    try {
      await store.dispatch(
        'summaryReports/fetchAuditoriaAdvisorDailyRollup',
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
const onAdvisorChange = () => fetchAllData();
</script>

<template>
  <ReportHeader
    :header-title="$t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.HEADER')"
    :header-description="
      $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.DESCRIPTION')
    "
  />

  <OverviewReportFilters
    :disabled="isLoading"
    hide-business-hours
    @filter-change="onFilterChange"
  />

  <div
    class="flex flex-wrap items-center gap-4 mt-3"
    :class="{ 'pointer-events-none opacity-50': isLoading }"
  >
    <div class="flex items-center gap-2">
      <label
        for="auditoria-rollup-advisor-filter"
        class="text-sm whitespace-nowrap"
      >
        {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.ADVISOR_FILTER_LABEL') }}
      </label>
      <select
        id="auditoria-rollup-advisor-filter"
        v-model="selectedUserId"
        class="reset-base !mb-0 !w-auto"
        :disabled="isLoading"
        @change="onAdvisorChange"
      >
        <option value="">
          {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.ADVISOR_FILTER_ALL') }}
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
        for="auditoria-rollup-inbox-filter"
        class="text-sm whitespace-nowrap"
      >
        {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.INBOX_FILTER_LABEL') }}
      </label>
      <select
        id="auditoria-rollup-inbox-filter"
        v-model="selectedInboxId"
        class="reset-base !mb-0 !w-auto"
        :disabled="isLoading"
        @change="onInboxChange"
      >
        <option value="">
          {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.INBOX_FILTER_ALL') }}
        </option>
        <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
          {{ inbox.name }}
        </option>
      </select>
    </div>
    <div class="flex items-center gap-2">
      <label
        for="auditoria-rollup-positive-tag-filter"
        class="text-sm whitespace-nowrap"
      >
        {{
          $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.POSITIVE_TAG_FILTER_LABEL')
        }}
      </label>
      <select
        id="auditoria-rollup-positive-tag-filter"
        v-model="selectedPositiveTag"
        class="reset-base !mb-0 !w-auto"
        :disabled="isLoading"
      >
        <option value="">
          {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.TAG_FILTER_ALL') }}
        </option>
        <option v-for="tag in availablePositiveTags" :key="tag" :value="tag">
          {{ tag }}
        </option>
      </select>
    </div>
    <div class="flex items-center gap-2">
      <label
        for="auditoria-rollup-negative-tag-filter"
        class="text-sm whitespace-nowrap"
      >
        {{
          $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.NEGATIVE_TAG_FILTER_LABEL')
        }}
      </label>
      <select
        id="auditoria-rollup-negative-tag-filter"
        v-model="selectedNegativeTag"
        class="reset-base !mb-0 !w-auto"
        :disabled="isLoading"
      >
        <option value="">
          {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.TAG_FILTER_ALL') }}
        </option>
        <option v-for="tag in availableNegativeTags" :key="tag" :value="tag">
          {{ tag }}
        </option>
      </select>
    </div>
    <div class="flex items-center gap-2">
      <label for="auditoria-rollup-sort" class="text-sm whitespace-nowrap">
        {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.SORT_LABEL') }}
      </label>
      <select
        id="auditoria-rollup-sort"
        v-model="sortBy"
        class="reset-base !mb-0 !w-auto"
        :disabled="isLoading"
      >
        <option value="date">
          {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.SORT_BY_DATE') }}
        </option>
        <option value="name">
          {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.SORT_BY_NAME') }}
        </option>
      </select>
    </div>
  </div>

  <div v-if="isLoading" class="flex items-center justify-center py-16">
    <Spinner :size="32" class="text-n-brand" />
  </div>

  <EmptyState
    v-else-if="!displayedSummaries.length"
    :title="$t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.EMPTY_TITLE')"
    :message="$t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.EMPTY_MESSAGE')"
  />

  <div v-else class="flex flex-col gap-3 mt-5">
    <div
      v-for="row in displayedSummaries"
      :key="`${row.userId}-${row.summaryDate}`"
      class="flex flex-col gap-2 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-2"
    >
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div class="flex items-center gap-2">
          <Avatar
            :src="advisorThumbnail(row.userId)"
            :name="advisorName(row.userId)"
            :size="28"
          />
          <span class="text-sm font-medium text-n-slate-12">
            <button
              type="button"
              class="text-n-blue-text hover:underline"
              @click="openConversationsDrawer(row)"
            >
              {{ advisorName(row.userId) }}
            </button>
            <span class="text-n-slate-10 font-normal">
              · {{ formatSummaryDate(row.summaryDate) }}
            </span>
          </span>
        </div>
        <span class="text-xs text-n-slate-10">
          {{
            $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.CONVERSATIONS_COUNT', {
              count: row.conversationsCount,
            })
          }}
        </span>
      </div>

      <p v-if="row.generatedAt" class="text-xs text-n-slate-10">
        {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.GENERATED_AT_LABEL') }}:
        {{ formatGeneratedAt(row.generatedAt) }}
      </p>

      <p v-if="row.results?.summary" class="text-sm text-n-slate-11">
        <span class="font-medium text-n-slate-12">
          {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.SUMMARY_LABEL') }}:
        </span>
        {{ row.results.summary }}
      </p>
      <p v-if="row.results?.toneOverview" class="text-sm text-n-slate-11">
        <span class="font-medium text-n-slate-12">
          {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.TONE_LABEL') }}:
        </span>
        {{ row.results.toneOverview }}
      </p>
      <p v-if="row.results?.recommendation" class="text-sm text-n-slate-11">
        <span class="font-medium text-n-slate-12">
          {{
            $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.RECOMMENDATION_LABEL')
          }}:
        </span>
        {{ row.results.recommendation }}
      </p>

      <p
        v-if="row.results?.shortFeedback"
        v-tooltip.top="row.results?.shortFeedbackReason"
        class="text-sm text-n-amber-11 bg-n-amber-2 rounded-lg px-3 py-2"
      >
        <span class="font-medium">
          {{
            $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.SHORT_FEEDBACK_LABEL')
          }}:
        </span>
        {{ row.results.shortFeedback }}
      </p>

      <div
        v-if="row.feedbackTagsPositive?.length"
        class="flex flex-wrap items-center gap-2 mt-1"
      >
        <span class="text-xs text-n-slate-10">
          {{
            $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.POSITIVE_TAGS_LABEL')
          }}:
        </span>
        <span
          v-for="tag in row.feedbackTagsPositive"
          :key="tag"
          class="text-xs px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
        >
          {{ tag }}
        </span>
      </div>

      <div
        v-if="row.feedbackTagsNegative?.length"
        class="flex flex-wrap items-center gap-2 mt-1"
      >
        <span class="text-xs text-n-slate-10">
          {{
            $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.NEGATIVE_TAGS_LABEL')
          }}:
        </span>
        <button
          v-for="tag in row.feedbackTagsNegative"
          :key="tag"
          v-tooltip.top="negativeDetailFor(row, tag).reason"
          type="button"
          class="text-xs px-2 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11 hover:bg-n-amber-4"
          @click="openCitationDrawer(negativeDetailFor(row, tag))"
        >
          {{ tag }}
        </button>
      </div>

      <div
        v-if="categoryChips(row).length"
        class="flex flex-wrap items-center gap-2 mt-1"
      >
        <span class="text-xs text-n-slate-10">
          {{ $t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.CATEGORIES_LABEL') }}:
        </span>
        <span
          v-for="chip in categoryChips(row)"
          :key="chip.title"
          class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-1 text-n-slate-11"
        >
          {{ chip.title }}: {{ chip.count }}
        </span>
      </div>
    </div>
  </div>

  <AuditoriaReportConversationsDrawer
    :open="isDrawerOpen"
    :title="selectedSummary ? advisorName(selectedSummary.userId) : ''"
    :description="
      t(
        'AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.CONVERSATIONS_DRAWER.DESCRIPTION'
      )
    "
    :empty-text="
      t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.CONVERSATIONS_DRAWER.EMPTY')
    "
    :error-text="
      t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.CONVERSATIONS_DRAWER.ERROR')
    "
    :filter-params="drawerFilterParams"
    :fetcher="fetchDayConversations"
    @close="closeConversationsDrawer"
  />

  <AuditoriaReportConversationsDrawer
    :open="isCitationDrawerOpen"
    :title="selectedCitation?.tag"
    :description="selectedCitation?.reason"
    :empty-text="
      t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.CITATION_DRAWER.EMPTY')
    "
    :error-text="
      t('AUDITORIA_ADVISOR_DAILY_ROLLUP_REPORTS.CONVERSATIONS_DRAWER.ERROR')
    "
    :filter-params="citationDrawerFilterParams"
    :fetcher="fetchCitationConversations"
    @close="closeCitationDrawer"
  />
</template>

<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import AuditoriaReportConversationsDrawer from './components/AuditoriaReportConversationsDrawer.vue';
import CategoryMentionsChart from './components/CategoryMentionsChart.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SummaryReportsAPI from 'dashboard/api/summaryReports';

const { t } = useI18n();
const store = useStore();

// Numero de categorias marcadas por defecto en la grafica -- las primeras
// 3 son las que la paleta categorica (skill dataviz) garantiza distintas
// incluso comparadas todas contra todas; con mas, la comparacion sigue
// siendo segura (son pares adyacentes en una linea, no todas-contra-todas)
// pero arrancar con pocas evita una grafica saturada antes de que el
// usuario elija que comparar.
const DEFAULT_CHECKED_COUNT = 3;

const from = ref(0);
const to = ref(0);
const selectedInboxId = ref('');
const checkedCategoryIds = ref(new Set());

const uiFlags = useMapGetter('summaryReports/getUIFlags');
const isLoading = computed(
  () => uiFlags.value.isFetchingAuditoriaCategorySummaryReports ?? false
);

const inboxes = useMapGetter('inboxes/getInboxes');
const categories = useMapGetter(
  'summaryReports/getAuditoriaCategorySummaryReports'
);
const reportTotals = useMapGetter(
  'summaryReports/getAuditoriaCategorySummaryTotals'
);
const timeseries = useMapGetter(
  'summaryReports/getAuditoriaCategoryTimeseries'
);

const renderCount = value => (value ? value.toLocaleString() : '--');

const isChecked = id => checkedCategoryIds.value.has(id);

const fetchSummary = async () => {
  const params = { inboxId: selectedInboxId.value || undefined };
  try {
    await store.dispatch(
      'summaryReports/fetchAuditoriaCategorySummaryReports',
      params
    );
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
    return;
  }

  // Primera carga: marca las primeras categorias por defecto para que la
  // grafica no arranque vacia.
  if (checkedCategoryIds.value.size === 0 && categories.value.length) {
    checkedCategoryIds.value = new Set(
      categories.value.slice(0, DEFAULT_CHECKED_COUNT).map(c => c.id)
    );
  }
};

const fetchTimeseries = async () => {
  if (!checkedCategoryIds.value.size) return;

  const params = {
    since: from.value,
    until: to.value,
    inboxId: selectedInboxId.value || undefined,
    categoryIds: Array.from(checkedCategoryIds.value),
  };
  try {
    await store.dispatch(
      'summaryReports/fetchAuditoriaCategoryTimeseries',
      params
    );
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
  }
};

const toggleChecked = id => {
  const next = new Set(checkedCategoryIds.value);
  if (next.has(id)) {
    next.delete(id);
  } else {
    next.add(id);
  }
  checkedCategoryIds.value = next;
  fetchTimeseries();
};

const fetchAllData = async () => {
  await fetchSummary();
  fetchTimeseries();
};

onMounted(() => fetchAllData());

const onFilterChange = updatedFilter => {
  from.value = updatedFilter.from;
  to.value = updatedFilter.to;
  fetchAllData();
};

const onInboxChange = () => fetchAllData();

const totalsSummary = computed(() => {
  if (!reportTotals.value) return '';

  return t('AUDITORIA_CATEGORY_REPORTS.TOTALS_SUMMARY', {
    conversations: renderCount(reportTotals.value.conversationsCount),
  });
});

const selectedCategory = ref(null);
const isDrawerOpen = computed(() => !!selectedCategory.value);
const openCategoryDrawer = category => {
  selectedCategory.value = category;
};
const closeCategoryDrawer = () => {
  selectedCategory.value = null;
};
const fetchCategoryConversations = params =>
  SummaryReportsAPI.getAuditoriaCategoryConversations(params);
</script>

<template>
  <ReportHeader
    :header-title="$t('AUDITORIA_CATEGORY_REPORTS.HEADER')"
    :header-description="$t('AUDITORIA_CATEGORY_REPORTS.DESCRIPTION')"
  />

  <div class="flex flex-col justify-between gap-3 md:flex-row">
    <OverviewReportFilters
      :disabled="isLoading"
      @filter-change="onFilterChange"
    />
    <div
      class="flex items-center gap-2"
      :class="{ 'pointer-events-none opacity-50': isLoading }"
    >
      <label
        for="auditoria-category-inbox-filter"
        class="text-sm whitespace-nowrap"
      >
        {{ $t('AUDITORIA_CATEGORY_REPORTS.INBOX_FILTER_LABEL') }}
      </label>
      <select
        id="auditoria-category-inbox-filter"
        v-model="selectedInboxId"
        class="reset-base !mb-0 !w-auto"
        :disabled="isLoading"
        @change="onInboxChange"
      >
        <option value="">
          {{ $t('AUDITORIA_CATEGORY_REPORTS.INBOX_FILTER_ALL') }}
        </option>
        <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
          {{ inbox.name }}
        </option>
      </select>
    </div>
  </div>

  <div
    class="relative mt-5 rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
  >
    <CategoryMentionsChart :series="timeseries" :since="from" :until="to" />
    <div
      v-if="isLoading"
      class="absolute inset-0 flex items-center justify-center rounded-xl bg-n-solid-1/70"
    >
      <Spinner :size="32" class="text-n-brand" />
    </div>
  </div>

  <div
    class="relative flex-1 overflow-auto px-2 py-2 mt-5 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <table class="min-w-full table-auto divide-y divide-n-weak">
      <thead class="border-t border-n-weak">
        <tr>
          <th
            class="py-4 ltr:pr-4 rtl:pl-4 text-start text-heading-3 text-n-slate-12"
          >
            {{ $t('AUDITORIA_CATEGORY_REPORTS.TABLE.SHOW_IN_CHART') }}
          </th>
          <th
            class="py-4 ltr:pr-4 rtl:pl-4 text-start text-heading-3 text-n-slate-12"
          >
            {{ $t('AUDITORIA_CATEGORY_REPORTS.TABLE.TITLE') }}
          </th>
          <th
            class="py-4 ltr:pr-4 rtl:pl-4 text-start text-heading-3 text-n-slate-12"
          >
            {{ $t('AUDITORIA_CATEGORY_REPORTS.TABLE.CONVERSATIONS') }}
          </th>
        </tr>
      </thead>
      <tbody class="divide-y divide-n-weak text-n-slate-11">
        <tr v-for="category in categories" :key="category.id">
          <td class="py-3 ltr:pr-4 rtl:pl-4">
            <input
              type="checkbox"
              :checked="isChecked(category.id)"
              @change="toggleChecked(category.id)"
            />
          </td>
          <td class="py-3 ltr:pr-4 rtl:pl-4 text-body-main">
            <button
              type="button"
              class="text-n-blue-text hover:underline"
              @click="openCategoryDrawer(category)"
            >
              {{ category.title }}
            </button>
          </td>
          <td class="py-3 ltr:pr-4 rtl:pl-4 text-body-main">
            {{ renderCount(category.conversationsCount) }}
          </td>
        </tr>
      </tbody>
    </table>
  </div>

  <p v-if="totalsSummary" class="text-sm text-n-slate-11 mt-2 text-right">
    {{ totalsSummary }}
  </p>

  <AuditoriaReportConversationsDrawer
    :open="isDrawerOpen"
    :title="selectedCategory?.title"
    :description="
      $t('AUDITORIA_CATEGORY_REPORTS.CONVERSATIONS_DRAWER.DESCRIPTION')
    "
    :empty-text="$t('AUDITORIA_CATEGORY_REPORTS.CONVERSATIONS_DRAWER.EMPTY')"
    :error-text="$t('AUDITORIA_CATEGORY_REPORTS.CONVERSATIONS_DRAWER.ERROR')"
    :filter-params="{
      categoryId: selectedCategory?.id,
      inboxId: selectedInboxId,
    }"
    :fetcher="fetchCategoryConversations"
    @close="closeCategoryDrawer"
  />
</template>

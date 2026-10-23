<script setup>
import { computed, onMounted, ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ReportHeader from './components/ReportHeader.vue';
import OverviewReportFilters from './components/OverviewReportFilters.vue';
import AuditoriaReportConversationsDrawer from './components/AuditoriaReportConversationsDrawer.vue';
import CategoryMentionsChart from './components/CategoryMentionsChart.vue';
import CategoryBreakdownPieChart from './components/CategoryBreakdownPieChart.vue';
import TermsBreakdownList from './components/TermsBreakdownList.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import SummaryReportsAPI from 'dashboard/api/summaryReports';
import {
  downloadCsvFile,
  generateFileName,
} from 'dashboard/helper/downloadHelper';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const createCategoryRoute = computed(() => ({
  name: 'settings_applications_integration',
  params: { accountId: route.params.accountId, integration_id: 'openai' },
  hash: '#categories',
}));

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
const countMode = ref('conversations');
const checkedCategoryIds = ref(new Set());
const expandedParentIds = ref(new Set());

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
const timeseriesBucket = useMapGetter(
  'summaryReports/getAuditoriaCategoryTimeseriesBucket'
);

// Arbol de 2 niveles a partir de la lista plana que ya trae parent_id
// (ver V2::Reports::AuditoriaCategorySummaryBuilder) -- las filas de nivel
// superior se muestran siempre; las hijas solo cuando su padre esta
// expandido.
const topLevelCategories = computed(() =>
  categories.value.filter(c => !c.parentId)
);
const childrenByParentId = computed(() => {
  const map = {};
  categories.value.forEach(category => {
    if (!category.parentId) return;
    (map[category.parentId] ||= []).push(category);
  });
  return map;
});

// Distribucion general entre categorias de nivel superior (rollup de sus
// hijas cuando aplica, ver AuditoriaCategorySummaryBuilder) -- con una sola
// categoria configurada no hay nada que comparar, asi que la seccion entera
// se oculta (ver template).
const topLevelPieSegments = computed(() =>
  topLevelCategories.value.map(category => ({
    id: category.id,
    title: category.title,
    count: category.conversationsCount,
  }))
);

const isExpanded = id => expandedParentIds.value.has(id);
const toggleExpanded = id => {
  const next = new Set(expandedParentIds.value);
  if (next.has(id)) {
    next.delete(id);
  } else {
    next.add(id);
  }
  expandedParentIds.value = next;
};

// Desglose por termino de busqueda de una categoria HOJA de palabra clave
// (ver V2::Reports::AuditoriaCategoryTermsBuilder) -- se pide perezoso al
// expandir, y se cachea por id para no re-pedirlo si se colapsa y se vuelve
// a abrir la misma categoria. El cache es sensible a fecha/bandeja (ver
// toggleTerms), asi que resetTermsState lo vacia cuando esos filtros
// cambian para no mostrar conteos de un rango que ya no es el seleccionado.
const expandedTermCategoryIds = ref(new Set());
const termsByCategoryId = ref({});
const resetTermsState = () => {
  expandedTermCategoryIds.value = new Set();
  termsByCategoryId.value = {};
};

const isTermsExpanded = id => expandedTermCategoryIds.value.has(id);
const toggleTerms = async category => {
  const next = new Set(expandedTermCategoryIds.value);
  if (next.has(category.id)) {
    next.delete(category.id);
    expandedTermCategoryIds.value = next;
    return;
  }
  next.add(category.id);
  expandedTermCategoryIds.value = next;

  if (termsByCategoryId.value[category.id]) return;

  termsByCategoryId.value = {
    ...termsByCategoryId.value,
    [category.id]: { isLoading: true, terms: [] },
  };
  try {
    const { data } = await SummaryReportsAPI.getAuditoriaCategoryTerms({
      since: from.value,
      until: to.value,
      categoryId: category.id,
      inboxId: selectedInboxId.value || undefined,
      countMode: countMode.value,
    });
    termsByCategoryId.value = {
      ...termsByCategoryId.value,
      [category.id]: {
        isLoading: false,
        terms: camelcaseKeys(data.terms, { deep: true }),
      },
    };
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
    termsByCategoryId.value = {
      ...termsByCategoryId.value,
      [category.id]: { isLoading: false, terms: [] },
    };
  }
};

const renderCount = value => (value ? value.toLocaleString() : '--');

const isChecked = id => checkedCategoryIds.value.has(id);

const fetchSummary = async () => {
  const params = {
    since: from.value,
    until: to.value,
    inboxId: selectedInboxId.value || undefined,
    countMode: countMode.value,
  };
  try {
    await store.dispatch(
      'summaryReports/fetchAuditoriaCategorySummaryReports',
      params
    );
  } catch {
    useAlert(t('REPORT.SUMMARY_FETCHING_FAILED'));
    return;
  }

  // Primera carga: marca las primeras categorias HOJA (las unicas con
  // datos propios para graficar -- ver Auditoria::Category.leaf) por
  // defecto para que la grafica no arranque vacia.
  if (checkedCategoryIds.value.size === 0) {
    const leaves = categories.value.filter(c => !c.hasSubcategories);
    checkedCategoryIds.value = new Set(
      leaves.slice(0, DEFAULT_CHECKED_COUNT).map(c => c.id)
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
    countMode: countMode.value,
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

  if (next.size) {
    fetchTimeseries();
  } else {
    // Vacia la grafica de inmediato -- fetchTimeseries corta temprano
    // cuando no hay categorias marcadas, lo que antes dejaba la grafica
    // mostrando la seleccion anterior en vez de quedar vacia al instante.
    store.commit('summaryReports/setAuditoriaCategoryTimeseries', {});
  }
};

const fetchAllData = async () => {
  resetTermsState();
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
// Re-pide tanto el resumen (tabla/totales) como la serie de tiempo -- ambos
// aceptan count_mode con el mismo criterio (crudo vs. distinct por
// conversation_id), ver V2::Reports::AuditoriaCategorySummaryBuilder y
// ...TimeseriesBuilder.
const onCountModeChange = () => {
  resetTermsState();
  fetchSummary();
  fetchTimeseries();
};

const totalsSummary = computed(() => {
  if (!reportTotals.value) return '';

  return t('AUDITORIA_CATEGORY_REPORTS.TOTALS_SUMMARY', {
    conversations: renderCount(reportTotals.value.conversationsCount),
  });
});

const selectedCategory = ref(null);
const selectedTerm = ref(null);
const isDrawerOpen = computed(() => !!selectedCategory.value);
const openCategoryDrawer = category => {
  selectedCategory.value = category;
  selectedTerm.value = null;
};
// Clic en un termino del desglose -- mismo drawer, pero filtrado a ese
// termino puntual (ver auditoria_category_conversations_params#term).
const openTermDrawer = (category, term) => {
  selectedCategory.value = category;
  selectedTerm.value = term;
};
const closeCategoryDrawer = () => {
  selectedCategory.value = null;
  selectedTerm.value = null;
};
const fetchCategoryConversations = params =>
  SummaryReportsAPI.getAuditoriaCategoryConversations(params);

const downloadCsv = async (fetchCsv, fileType) => {
  try {
    const { data } = await fetchCsv();
    downloadCsvFile(generateFileName({ type: fileType, to: to.value }), data);
  } catch {
    useAlert(t('AUDITORIA_CATEGORY_REPORTS.EXPORT_FAILED'));
  }
};

const isDownloadingCategoryCsv = ref(false);
const downloadCategoryCsv = async () => {
  isDownloadingCategoryCsv.value = true;
  await downloadCsv(
    () =>
      SummaryReportsAPI.getAuditoriaCategoryCsv({
        since: from.value,
        until: to.value,
        inboxId: selectedInboxId.value || undefined,
        countMode: countMode.value,
      }),
    'auditoria_category'
  );
  isDownloadingCategoryCsv.value = false;
};

const isDownloadingTimeseriesCsv = ref(false);
const downloadTimeseriesCsv = async () => {
  isDownloadingTimeseriesCsv.value = true;
  await downloadCsv(
    () =>
      SummaryReportsAPI.getAuditoriaCategoryTimeseriesCsv({
        since: from.value,
        until: to.value,
        inboxId: selectedInboxId.value || undefined,
        categoryIds: Array.from(checkedCategoryIds.value),
        countMode: countMode.value,
      }),
    'auditoria_category_timeseries'
  );
  isDownloadingTimeseriesCsv.value = false;
};

const exportConversationsCsv = params =>
  downloadCsv(
    () => SummaryReportsAPI.getAuditoriaCategoryConversationsCsv(params),
    'auditoria_category_conversations'
  );

const goToCreateCategory = () => router.push(createCategoryRoute.value);
</script>

<template>
  <ReportHeader
    :header-title="$t('AUDITORIA_CATEGORY_REPORTS.HEADER')"
    :header-description="$t('AUDITORIA_CATEGORY_REPORTS.DESCRIPTION')"
  />
  <Button
    size="sm"
    class="-mt-3 mb-3"
    :label="$t('AUDITORIA_CATEGORY_REPORTS.CREATE_CATEGORY_LINK')"
    @click="goToCreateCategory"
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
        <label
          for="auditoria-category-count-mode"
          class="text-sm whitespace-nowrap"
        >
          {{ $t('AUDITORIA_CATEGORY_REPORTS.COUNT_MODE_LABEL') }}
        </label>
        <select
          id="auditoria-category-count-mode"
          v-model="countMode"
          class="reset-base !mb-0 !w-auto"
          :disabled="isLoading"
          @change="onCountModeChange"
        >
          <option value="conversations">
            {{ $t('AUDITORIA_CATEGORY_REPORTS.COUNT_MODE.CONVERSATIONS') }}
          </option>
          <option value="mentions">
            {{ $t('AUDITORIA_CATEGORY_REPORTS.COUNT_MODE.MENTIONS') }}
          </option>
        </select>
      </div>
      <div class="flex items-center gap-2">
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
  </div>

  <div class="flex items-center justify-end mt-5">
    <Button
      faded
      slate
      size="sm"
      icon="i-ph-download-simple"
      :label="$t('AUDITORIA_CATEGORY_REPORTS.EXPORT_CSV_BUTTON')"
      :is-loading="isDownloadingTimeseriesCsv"
      @click="downloadTimeseriesCsv"
    />
  </div>
  <div
    class="relative mt-2 rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
  >
    <CategoryMentionsChart
      :series="timeseries"
      :since="from"
      :until="to"
      :bucket="timeseriesBucket"
    />
    <div
      v-if="isLoading"
      class="absolute inset-0 flex items-center justify-center rounded-xl bg-n-solid-1/70"
    >
      <Spinner :size="32" class="text-n-brand" />
    </div>
  </div>

  <div
    v-if="topLevelPieSegments.length > 1"
    class="mt-5 rounded-xl bg-n-solid-2 p-4 shadow outline-1 outline outline-n-container"
  >
    <p class="text-sm font-medium text-n-slate-12 mb-3">
      {{ $t('AUDITORIA_CATEGORY_REPORTS.OVERALL_BREAKDOWN.TITLE') }}
    </p>
    <CategoryBreakdownPieChart :segments="topLevelPieSegments" />
  </div>

  <div class="flex items-center justify-end mt-5">
    <Button
      faded
      slate
      size="sm"
      icon="i-ph-download-simple"
      :label="$t('AUDITORIA_CATEGORY_REPORTS.EXPORT_CSV_BUTTON')"
      :is-loading="isDownloadingCategoryCsv"
      @click="downloadCategoryCsv"
    />
  </div>
  <div
    class="relative flex-1 overflow-auto px-2 py-2 mt-2 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2"
  >
    <table class="min-w-full table-auto divide-y divide-n-weak">
      <thead>
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
        <template v-for="category in topLevelCategories" :key="category.id">
          <tr>
            <td class="py-3 ltr:pr-4 rtl:pl-4">
              <!-- Una categoria agrupadora nunca tiene datos propios para
                   graficar -- solo sus subcategorias los tienen (ver
                   Auditoria::Category.leaf). -->
              <Checkbox
                v-if="!category.hasSubcategories"
                :model-value="isChecked(category.id)"
                @change="toggleChecked(category.id)"
              />
            </td>
            <td class="py-3 ltr:pr-4 rtl:pl-4 text-body-main">
              <div class="flex items-center gap-1">
                <button
                  v-if="category.hasSubcategories"
                  type="button"
                  class="flex items-center justify-center size-5 text-n-slate-10 hover:text-n-slate-12"
                  @click="toggleExpanded(category.id)"
                >
                  <Icon
                    :icon="
                      isExpanded(category.id)
                        ? 'i-lucide-chevron-up'
                        : 'i-lucide-chevron-down'
                    "
                    class="size-4"
                  />
                </button>
                <button
                  type="button"
                  class="text-n-blue-text hover:underline"
                  @click="openCategoryDrawer(category)"
                >
                  {{ category.title }}
                </button>
                <button
                  v-if="
                    !category.hasSubcategories &&
                    category.matchType === 'keyword'
                  "
                  type="button"
                  class="text-xs text-n-slate-10 hover:text-n-slate-12 hover:underline"
                  @click="toggleTerms(category)"
                >
                  {{ $t('AUDITORIA_CATEGORY_REPORTS.TERMS_BREAKDOWN.TOGGLE') }}
                </button>
              </div>
            </td>
            <td class="py-3 ltr:pr-4 rtl:pl-4 text-body-main">
              {{ renderCount(category.conversationsCount) }}
            </td>
          </tr>
          <tr v-if="category.hasSubcategories && isExpanded(category.id)">
            <td colspan="3" class="pb-3 ltr:pr-4 rtl:pl-4">
              <CategoryBreakdownPieChart
                :segments="
                  (childrenByParentId[category.id] || []).map(child => ({
                    id: child.id,
                    title: child.title,
                    count: child.conversationsCount,
                  }))
                "
              />
            </td>
          </tr>
          <tr v-if="!category.hasSubcategories && isTermsExpanded(category.id)">
            <td colspan="3" class="pb-3 ltr:pr-4 rtl:pl-4">
              <TermsBreakdownList
                :state="termsByCategoryId[category.id]"
                @select-term="term => openTermDrawer(category, term)"
              />
            </td>
          </tr>
          <template
            v-for="child in category.hasSubcategories && isExpanded(category.id)
              ? childrenByParentId[category.id] || []
              : []"
            :key="child.id"
          >
            <tr>
              <td class="py-3 ltr:pr-4 rtl:pl-4 ps-8">
                <Checkbox
                  :model-value="isChecked(child.id)"
                  @change="toggleChecked(child.id)"
                />
              </td>
              <td class="py-3 ltr:pr-4 rtl:pl-4 ps-8 text-body-main">
                <div class="flex items-center gap-1">
                  <button
                    type="button"
                    class="text-n-blue-text hover:underline"
                    @click="openCategoryDrawer(child)"
                  >
                    {{ child.title }}
                  </button>
                  <button
                    v-if="child.matchType === 'keyword'"
                    type="button"
                    class="text-xs text-n-slate-10 hover:text-n-slate-12 hover:underline"
                    @click="toggleTerms(child)"
                  >
                    {{
                      $t('AUDITORIA_CATEGORY_REPORTS.TERMS_BREAKDOWN.TOGGLE')
                    }}
                  </button>
                </div>
              </td>
              <td class="py-3 ltr:pr-4 rtl:pl-4 text-body-main">
                {{ renderCount(child.conversationsCount) }}
              </td>
            </tr>
            <tr v-if="isTermsExpanded(child.id)">
              <td colspan="3" class="pb-3 ltr:pr-4 rtl:pl-4 ps-8">
                <TermsBreakdownList
                  :state="termsByCategoryId[child.id]"
                  @select-term="term => openTermDrawer(child, term)"
                />
              </td>
            </tr>
          </template>
        </template>
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
      since: from,
      until: to,
      categoryId: selectedCategory?.id,
      inboxId: selectedInboxId,
      term: selectedTerm,
    }"
    :fetcher="fetchCategoryConversations"
    :export-csv="exportConversationsCsv"
    sortable-by-reason
    @close="closeCategoryDrawer"
  />
</template>

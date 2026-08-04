<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import startOfMonth from 'date-fns/startOfMonth';
import parseISO from 'date-fns/parseISO';
import format from 'date-fns/format';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactAPI from 'dashboard/api/contacts';
import AttributeStatCard from './components/AttributeStatCard.vue';
import ContactsPreviewPanel from './components/ContactsPreviewPanel.vue';
import ContactDailyTrendCard from './components/ContactDailyTrendCard.vue';
import ContactHourlyCard from './components/ContactHourlyCard.vue';

const { t } = useI18n();
const store = useStore();

const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');

const customDateRange = ref([startOfMonth(new Date()), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.MONTH_TO_DATE);
const selectedInboxId = ref('');
const selectedLabelTitles = ref([]);
const activeFilters = ref({});
const isFetching = ref(false);
const isExporting = ref(false);
const stats = ref({
  total_count: 0,
  keys: [],
  breakdowns: {},
  daily_series: [],
  hourly_series: [],
});

const dayFilter = ref(null);

const since = computed(() => getUnixStartOfDay(customDateRange.value[0]));
const until = computed(() => getUnixEndOfDay(customDateRange.value[1]));

const activeFilterEntries = computed(() => Object.entries(activeFilters.value));

const activeLabelObjects = computed(() =>
  labels.value.filter(label => selectedLabelTitles.value.includes(label.title))
);

const inboxOptions = computed(() => [
  { value: '', label: t('CONTACT_STATS.ALL_INBOXES') },
  ...inboxes.value.map(inbox => ({
    value: String(inbox.id),
    label: inbox.name,
  })),
]);

const humanize = key =>
  key.replace(/_/g, ' ').replace(/\b\w/g, char => char.toUpperCase());

const requestFilters = computed(() => ({
  since: since.value,
  until: until.value,
  filters: activeFilters.value,
  inboxId: selectedInboxId.value,
  labelTitles: selectedLabelTitles.value,
}));

const previewSince = computed(() => dayFilter.value?.since ?? since.value);
const previewUntil = computed(() => dayFilter.value?.until ?? until.value);
const dayFilterLabel = computed(() => dayFilter.value?.label ?? '');

const fetchStats = async () => {
  isFetching.value = true;
  try {
    const { data } = await ContactAPI.attributeStats(requestFilters.value);
    stats.value = data;
  } finally {
    isFetching.value = false;
  }
};

const onDateRangeChange = value => {
  const [startDate, endDate, rangeType] = value;
  customDateRange.value = [startDate, endDate];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
  dayFilter.value = null;
  fetchStats();
};

watch(selectedInboxId, fetchStats);

const toggleLabel = title => {
  selectedLabelTitles.value = selectedLabelTitles.value.includes(title)
    ? selectedLabelTitles.value.filter(selected => selected !== title)
    : [...selectedLabelTitles.value, title];
  fetchStats();
};

const clearFilter = key => {
  const updated = { ...activeFilters.value };
  delete updated[key];
  activeFilters.value = updated;
  fetchStats();
};

const clearAllFilters = () => {
  activeFilters.value = {};
  fetchStats();
};

const onSegmentSelect = ({ key, value }) => {
  if (!value) {
    clearFilter(key);
    return;
  }
  activeFilters.value = { ...activeFilters.value, [key]: value };
  fetchStats();
};

const onSelectDay = entry => {
  const day = parseISO(entry.date);
  dayFilter.value = {
    since: getUnixStartOfDay(day),
    until: getUnixEndOfDay(day),
    label: format(day, 'MMM d, yyyy'),
  };
};

const clearDayFilter = () => {
  dayFilter.value = null;
};

const onExport = async () => {
  isExporting.value = true;
  try {
    await ContactAPI.leadStatsExport(requestFilters.value);
    useAlert(t('CONTACT_STATS.EXPORT.SUCCESS'));
  } finally {
    isExporting.value = false;
  }
};

onMounted(() => {
  store.dispatch('labels/get');
  fetchStats();
});
</script>

<template>
  <div class="flex flex-col flex-1 h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex items-center gap-3 px-6 py-3 border-b border-n-weak flex-shrink-0"
    >
      <span class="i-lucide-chart-pie size-5 text-n-slate-11" />
      <h1 class="text-base font-semibold text-n-slate-12">
        {{ t('CONTACT_STATS.TITLE') }}
      </h1>
    </header>

    <div class="flex-1 overflow-y-auto p-6">
      <div class="flex flex-col items-start gap-3 mb-4">
        <div
          class="flex flex-col items-start gap-2 md:flex-row md:items-center md:flex-wrap"
        >
          <WootDatePicker
            v-model:date-range="customDateRange"
            v-model:range-type="selectedDateRange"
            @date-range-changed="onDateRangeChange"
          />
          <Select v-model="selectedInboxId" :options="inboxOptions" />
          <Button
            faded
            slate
            size="sm"
            icon="i-lucide-download"
            :is-loading="isExporting"
            :label="t('CONTACT_STATS.EXPORT.BUTTON')"
            @click="onExport"
          />
        </div>
        <div v-if="labels.length" class="flex flex-wrap items-center gap-1.5">
          <button
            v-for="label in labels"
            :key="label.id"
            type="button"
            class="flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs transition-colors"
            :class="
              selectedLabelTitles.includes(label.title)
                ? 'border-n-brand bg-n-brand/10 text-n-brand'
                : 'border-n-weak text-n-slate-11 hover:border-n-slate-6'
            "
            @click="toggleLabel(label.title)"
          >
            <span
              class="size-2 rounded-full"
              :style="{ backgroundColor: label.color }"
            />
            {{ label.title }}
          </button>
        </div>
      </div>

      <div
        v-if="activeFilterEntries.length"
        class="flex flex-wrap items-center gap-2 mb-4"
      >
        <span class="text-xs text-n-slate-10">
          {{ t('CONTACT_STATS.FILTERED_BY') }}
        </span>
        <button
          v-for="[key, value] in activeFilterEntries"
          :key="key"
          class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-brand/10 text-n-brand hover:bg-n-brand/20"
          @click="clearFilter(key)"
        >
          {{ humanize(key) }}: {{ value }}
          <span class="i-lucide-x size-3" />
        </button>
        <button
          class="text-xs underline text-n-slate-10 hover:text-n-slate-12"
          @click="clearAllFilters"
        >
          {{ t('CONTACT_STATS.CLEAR_ALL_FILTERS') }}
        </button>
      </div>

      <span
        v-if="isFetching"
        class="flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{ t('CONTACT_STATS.LOADING') }}
      </span>
      <span
        v-else-if="!stats.total_count"
        class="flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{ t('CONTACT_STATS.EMPTY_STATE') }}
      </span>
      <template v-else>
        <div
          class="flex flex-col justify-center p-4 mb-4 border rounded-xl border-n-weak bg-n-solid-1 w-fit"
        >
          <span class="text-xs text-n-slate-10">
            {{ t('CONTACT_STATS.TOTAL_LABEL') }}
          </span>
          <span class="text-2xl font-semibold text-n-slate-12">
            {{ stats.total_count }}
          </span>
        </div>

        <div class="grid grid-cols-1 gap-4 mb-4 lg:grid-cols-2">
          <ContactDailyTrendCard
            :daily-series="stats.daily_series"
            :active-labels="activeLabelObjects"
            :is-fetching="isFetching"
            @select-day="onSelectDay"
          />
          <ContactHourlyCard
            :hourly-series="stats.hourly_series"
            :is-fetching="isFetching"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <ContactsPreviewPanel
            :since="previewSince"
            :until="previewUntil"
            :filters="activeFilters"
            :inbox-id="selectedInboxId"
            :label-titles="selectedLabelTitles"
            :day-filter-label="dayFilterLabel"
            @clear-day-filter="clearDayFilter"
          />

          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <AttributeStatCard
              v-for="key in stats.keys"
              :key="key"
              :attribute-key="key"
              :label="humanize(key)"
              :breakdown="stats.breakdowns[key]"
              :active-value="activeFilters[key] || ''"
              @select="onSegmentSelect"
            />
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

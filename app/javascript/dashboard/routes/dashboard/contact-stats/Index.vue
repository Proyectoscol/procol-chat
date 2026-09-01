<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import startOfMonth from 'date-fns/startOfMonth';
import parseISO from 'date-fns/parseISO';
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

const contactAttributeDefinitions = useMapGetter(
  'attributes/getContactAttributes'
);

const customDateRange = ref([startOfMonth(new Date()), new Date()]);
const selectedDateRange = ref(DATE_RANGE_TYPES.MONTH_TO_DATE);
const selectedInboxId = ref('');
const selectedLabelTitles = ref([]);
const selectedContactIds = ref([]);
const activeFilters = ref({});
const activeCustomFilters = ref({});
const isFetching = ref(false);
const isExporting = ref(false);
const stats = ref({
  total_count: 0,
  keys: [],
  breakdowns: {},
  custom_keys: [],
  custom_breakdowns: {},
  label_counts: {},
  daily_series: [],
  hourly_series: [],
});

const previousDateRange = ref(null);
const hourFilter = ref(null);

const since = computed(() => getUnixStartOfDay(customDateRange.value[0]));
const until = computed(() => getUnixEndOfDay(customDateRange.value[1]));

const activeFilterEntries = computed(() => Object.entries(activeFilters.value));
const activeCustomFilterEntries = computed(() =>
  Object.entries(activeCustomFilters.value)
);

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

const customAttributeLabel = key =>
  contactAttributeDefinitions.value.find(a => a.attributeKey === key)
    ?.attributeDisplayName || humanize(key);

const requestFilters = computed(() => ({
  since: since.value,
  until: until.value,
  filters: activeFilters.value,
  customFilters: activeCustomFilters.value,
  inboxId: selectedInboxId.value,
  labelTitles: selectedLabelTitles.value,
  contactIds: selectedContactIds.value,
}));

const hourFilterLabel = computed(() => hourFilter.value?.label ?? '');

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
  previousDateRange.value = null;
  hourFilter.value = null;
  fetchStats();
};

watch(selectedInboxId, fetchStats);
watch(selectedContactIds, fetchStats, { deep: true });

const toggleLabel = title => {
  selectedLabelTitles.value = selectedLabelTitles.value.includes(title)
    ? selectedLabelTitles.value.filter(selected => selected !== title)
    : [...selectedLabelTitles.value, title];
  fetchStats();
};

const clearFilterFrom = (filtersRef, key) => {
  const updated = { ...filtersRef.value };
  delete updated[key];
  filtersRef.value = updated;
  fetchStats();
};

const setFilterFrom = (filtersRef, key, value) => {
  if (!value) {
    clearFilterFrom(filtersRef, key);
    return;
  }
  filtersRef.value = { ...filtersRef.value, [key]: value };
  fetchStats();
};

const clearFilter = key => clearFilterFrom(activeFilters, key);
const clearAllFilters = () => {
  activeFilters.value = {};
  activeCustomFilters.value = {};
  fetchStats();
};
const onSegmentSelect = ({ key, value }) =>
  setFilterFrom(activeFilters, key, value);

const clearCustomFilter = key => clearFilterFrom(activeCustomFilters, key);
const onCustomSegmentSelect = ({ key, value }) =>
  setFilterFrom(activeCustomFilters, key, value);

const clearContactSelection = () => {
  selectedContactIds.value = [];
};

const onSelectDay = entry => {
  const day = parseISO(entry.date);
  previousDateRange.value = {
    range: [...customDateRange.value],
    type: selectedDateRange.value,
  };
  customDateRange.value = [day, day];
  selectedDateRange.value = DATE_RANGE_TYPES.CUSTOM_RANGE;
  hourFilter.value = null;
  fetchStats();
};

const revertDayFilter = () => {
  if (!previousDateRange.value) return;
  customDateRange.value = previousDateRange.value.range;
  selectedDateRange.value = previousDateRange.value.type;
  previousDateRange.value = null;
  fetchStats();
};

const onSelectHour = ({ hour, label }) => {
  hourFilter.value = { hour, label };
};

const clearHourFilter = () => {
  hourFilter.value = null;
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
  store.dispatch('attributes/get');
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
          <Button
            v-if="previousDateRange"
            faded
            slate
            size="sm"
            icon="i-lucide-undo-2"
            :label="t('CONTACT_STATS.REVERT_DAY_FILTER')"
            @click="revertDayFilter"
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
            <span class="text-[10px] text-n-slate-10">
              {{ stats.label_counts?.[label.title] ?? 0 }}
            </span>
          </button>
        </div>
      </div>

      <div
        v-if="
          activeFilterEntries.length ||
          activeCustomFilterEntries.length ||
          selectedContactIds.length
        "
        class="flex flex-wrap items-center gap-2 mb-4"
      >
        <span class="text-xs text-n-slate-10">
          {{ t('CONTACT_STATS.FILTERED_BY') }}
        </span>
        <button
          v-for="[key, value] in activeFilterEntries"
          :key="`std-${key}`"
          class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-brand/10 text-n-brand hover:bg-n-brand/20"
          @click="clearFilter(key)"
        >
          {{ humanize(key) }}: {{ value }}
          <span class="i-lucide-x size-3" />
        </button>
        <button
          v-for="[key, value] in activeCustomFilterEntries"
          :key="`custom-${key}`"
          class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-brand/10 text-n-brand hover:bg-n-brand/20"
          @click="clearCustomFilter(key)"
        >
          {{ customAttributeLabel(key) }}: {{ value }}
          <span class="i-lucide-x size-3" />
        </button>
        <button
          v-if="selectedContactIds.length"
          class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-brand/10 text-n-brand hover:bg-n-brand/20"
          @click="clearContactSelection"
        >
          {{
            t('CONTACT_STATS.SELECTED_CONTACTS', {
              count: selectedContactIds.length,
            })
          }}
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
            @select-hour="onSelectHour"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <ContactsPreviewPanel
            v-model:selected-contact-ids="selectedContactIds"
            :since="since"
            :until="until"
            :filters="activeFilters"
            :custom-filters="activeCustomFilters"
            :inbox-id="selectedInboxId"
            :label-titles="selectedLabelTitles"
            :hour-of-day="hourFilter?.hour ?? null"
            :hour-filter-label="hourFilterLabel"
            @clear-hour-filter="clearHourFilter"
          />

          <div class="flex flex-col gap-4">
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

            <div v-if="stats.custom_keys?.length" class="flex flex-col gap-2">
              <h3
                class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
              >
                {{ t('CONTACT_STATS.CUSTOM_ATTRIBUTES.TITLE') }}
              </h3>
              <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <AttributeStatCard
                  v-for="key in stats.custom_keys"
                  :key="key"
                  :attribute-key="key"
                  :label="customAttributeLabel(key)"
                  :breakdown="stats.custom_breakdowns[key]"
                  :active-value="activeCustomFilters[key] || ''"
                  @select="onCustomSegmentSelect"
                />
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

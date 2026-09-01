<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BarChart from 'shared/components/charts/BarChart.vue';

const props = defineProps({
  hourlySeries: {
    type: Array,
    default: () => [],
  },
  isFetching: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['selectHour']);

const { t } = useI18n();

const formatHour = hour => {
  const period = hour < 12 ? 'am' : 'pm';
  const displayHour = hour % 12 === 0 ? 12 : hour % 12;
  return `${displayHour}${period}`;
};

const collection = computed(() => ({
  categories: props.hourlySeries.map(entry => formatHour(entry.hour)),
  series: [
    {
      id: 'total',
      label: t('CONTACT_STATS.HOURLY.TITLE'),
      color: '#1f93ff',
      data: props.hourlySeries.map(entry => entry.total),
    },
  ],
}));

const hasData = computed(() =>
  props.hourlySeries.some(entry => entry.total > 0)
);

const onElementClick = ({ pointIndex }) => {
  const entry = props.hourlySeries[pointIndex];
  if (!entry) return;

  emit('selectHour', { hour: entry.hour, label: formatHour(entry.hour) });
};
</script>

<template>
  <div class="flex flex-col rounded-xl border border-n-weak bg-n-solid-1 p-4">
    <h3 class="mb-3 text-sm font-medium text-n-slate-12">
      {{ t('CONTACT_STATS.HOURLY.TITLE') }}
    </h3>

    <span
      v-if="isFetching"
      class="flex h-56 items-center justify-center text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.LOADING') }}
    </span>
    <span
      v-else-if="!hasData"
      class="flex h-56 items-center justify-center text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.NO_DATA') }}
    </span>
    <div v-else class="h-56">
      <BarChart
        :data="collection"
        :aria-label="t('CONTACT_STATS.HOURLY.TITLE')"
        clickable
        @item-click="onElementClick"
      />
    </div>
  </div>
</template>

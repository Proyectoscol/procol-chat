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

const { t } = useI18n();

const formatHour = hour => {
  const period = hour < 12 ? 'am' : 'pm';
  const displayHour = hour % 12 === 0 ? 12 : hour % 12;
  return `${displayHour}${period}`;
};

const collection = computed(() => ({
  labels: props.hourlySeries.map(entry => formatHour(entry.hour)),
  datasets: [
    {
      label: t('CONTACT_STATS.HOURLY.TITLE'),
      data: props.hourlySeries.map(entry => entry.total),
      backgroundColor: '#1f93ff',
    },
  ],
}));

const hasData = computed(() =>
  props.hourlySeries.some(entry => entry.total > 0)
);
</script>

<template>
  <div class="flex flex-col rounded-xl border border-n-weak bg-n-solid-1 p-4">
    <h3 class="mb-3 text-sm font-medium text-n-slate-12">
      {{ t('CONTACT_STATS.HOURLY.TITLE') }}
    </h3>

    <span
      v-if="isFetching"
      class="flex h-40 items-center justify-center text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.LOADING') }}
    </span>
    <span
      v-else-if="!hasData"
      class="flex h-40 items-center justify-center text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.NO_DATA') }}
    </span>
    <div v-else class="h-40">
      <BarChart :collection="collection" />
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BarChart from 'shared/components/charts/BarChart.vue';
import DoughnutChart from 'shared/components/charts/DoughnutChart.vue';

const props = defineProps({
  attributeKey: {
    type: String,
    required: true,
  },
  label: {
    type: String,
    required: true,
  },
  breakdown: {
    type: Object,
    default: () => ({}),
  },
  activeValue: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['select']);

const { t } = useI18n();

const PALETTE = [
  '#1f93ff',
  '#37cb96',
  '#ffc532',
  '#ff5c5c',
  '#8b5cf6',
  '#f472b6',
  '#38bdf8',
  '#facc15',
  '#4ade80',
  '#fb923c',
  '#a3a3a3',
  '#22d3ee',
];

const entries = computed(() => Object.entries(props.breakdown));
const isDonut = computed(
  () => entries.value.length > 0 && entries.value.length <= 6
);
const chartComponent = computed(() =>
  isDonut.value ? DoughnutChart : BarChart
);

const collection = computed(() => ({
  labels: entries.value.map(([value]) => value),
  datasets: [
    {
      label: props.label,
      data: entries.value.map(([, count]) => count),
      backgroundColor: entries.value.map(
        (_, index) => PALETTE[index % PALETTE.length]
      ),
    },
  ],
}));

const onElementClick = ({ label }) => {
  emit('select', { key: props.attributeKey, value: label });
};
</script>

<template>
  <div class="flex flex-col p-4 border rounded-xl border-n-weak bg-n-solid-1">
    <div class="flex items-center justify-between gap-2 mb-3">
      <h3 class="text-sm font-medium truncate text-n-slate-12">
        {{ label }}
      </h3>
      <button
        v-if="activeValue"
        class="text-xs px-2 py-0.5 rounded-full bg-n-brand/10 text-n-brand hover:bg-n-brand/20 flex-shrink-0"
        @click="emit('select', { key: attributeKey, value: '' })"
      >
        {{ activeValue }}
        <span class="i-lucide-x size-3 ml-0.5 inline-block align-middle" />
      </button>
    </div>
    <div
      v-if="!entries.length"
      class="flex items-center justify-center py-8 text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.NO_DATA') }}
    </div>
    <div v-else class="h-48">
      <component
        :is="chartComponent"
        :collection="collection"
        clickable
        @element-click="onElementClick"
      />
    </div>
  </div>
</template>

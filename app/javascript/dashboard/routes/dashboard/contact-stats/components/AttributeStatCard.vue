<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

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
const total = computed(() =>
  entries.value.reduce((sum, [, count]) => sum + count, 0)
);

const rows = computed(() =>
  entries.value.map(([value, count], index) => ({
    value,
    count,
    percent: total.value ? Math.round((count / total.value) * 100) : 0,
    color: PALETTE[index % PALETTE.length],
  }))
);

const toggleValue = value => {
  emit('select', {
    key: props.attributeKey,
    value: props.activeValue === value ? '' : value,
  });
};
</script>

<template>
  <div class="flex flex-col p-4 border rounded-xl border-n-weak bg-n-solid-1">
    <div class="flex items-center justify-between gap-2 mb-3">
      <h3 class="text-sm font-medium truncate text-n-slate-12">
        {{ label }}
      </h3>
      <span class="text-xs flex-shrink-0 text-n-slate-10">{{ total }}</span>
    </div>

    <div
      v-if="!rows.length"
      class="flex items-center justify-center py-8 text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.NO_DATA') }}
    </div>

    <template v-else>
      <div
        class="flex w-full h-2.5 mb-3 overflow-hidden rounded-full bg-n-alpha-2"
      >
        <div
          v-for="row in rows"
          :key="row.value"
          :style="{ width: `${row.percent}%`, backgroundColor: row.color }"
          class="h-full first:rounded-s-full last:rounded-e-full"
        />
      </div>

      <ul class="flex flex-col gap-0.5 max-h-40 overflow-y-auto">
        <li v-for="row in rows" :key="row.value">
          <button
            type="button"
            class="flex items-center justify-between w-full gap-2 px-1.5 py-1 rounded-md text-left hover:bg-n-alpha-1"
            :class="{ 'bg-n-brand/10': activeValue === row.value }"
            @click="toggleValue(row.value)"
          >
            <span class="flex items-center min-w-0 gap-2">
              <span
                class="flex-shrink-0 rounded-full size-2"
                :style="{ backgroundColor: row.color }"
              />
              <span
                class="text-xs truncate"
                :class="
                  activeValue === row.value
                    ? 'font-medium text-n-brand'
                    : 'text-n-slate-12'
                "
              >
                {{ row.value }}
              </span>
            </span>
            <span
              class="flex items-center flex-shrink-0 gap-1 text-xs text-n-slate-10"
            >
              <span>{{ row.percent }}%</span>
              <span class="font-medium text-n-slate-12">{{ row.count }}</span>
            </span>
          </button>
        </li>
      </ul>
    </template>
  </div>
</template>

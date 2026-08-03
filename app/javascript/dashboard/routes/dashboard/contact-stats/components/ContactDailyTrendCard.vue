<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import format from 'date-fns/format';
import parseISO from 'date-fns/parseISO';
import { useEventListener } from '@vueuse/core';
import BarChart from 'shared/components/charts/BarChart.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  dailySeries: {
    type: Array,
    default: () => [],
  },
  activeLabels: {
    type: Array,
    default: () => [],
  },
  isFetching: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['selectDay']);

const { t } = useI18n();
const isExpanded = ref(false);

const TOTAL_COLOR = '#94a3b8';

const dayLabels = computed(() =>
  props.dailySeries.map(entry => format(parseISO(entry.date), 'MMM d'))
);

const collection = computed(() => ({
  labels: dayLabels.value,
  datasets: [
    {
      label: t('CONTACT_STATS.DAILY_TREND.TOTAL_DATASET'),
      data: props.dailySeries.map(entry => entry.total),
      backgroundColor: TOTAL_COLOR,
    },
    ...props.activeLabels.map(label => ({
      label: label.title,
      data: props.dailySeries.map(entry => entry.labels?.[label.title] || 0),
      backgroundColor: label.color,
    })),
  ],
}));

const hasData = computed(() =>
  props.dailySeries.some(entry => entry.total > 0)
);

const onElementClick = ({ dataIndex }) => {
  const entry = props.dailySeries[dataIndex];
  if (!entry) return;

  emit('selectDay', entry);
};

const onKeydown = event => {
  if (isExpanded.value && event.key === 'Escape') {
    isExpanded.value = false;
  }
};

useEventListener(document, 'keydown', onKeydown);
</script>

<template>
  <div class="flex flex-col rounded-xl border border-n-weak bg-n-solid-1 p-4">
    <div class="mb-3 flex items-center justify-between gap-2">
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('CONTACT_STATS.DAILY_TREND.TITLE') }}
      </h3>
      <Button
        ghost
        slate
        size="sm"
        icon="i-lucide-maximize-2"
        :aria-label="t('CONTACT_STATS.DAILY_TREND.EXPAND')"
        @click="isExpanded = true"
      />
    </div>

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
        :collection="collection"
        clickable
        @element-click="onElementClick"
      />
    </div>

    <TeleportWithDirection to="body">
      <Transition name="report-drilldown-fade">
        <div
          v-if="isExpanded"
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-6"
          role="presentation"
          @click.self="isExpanded = false"
        >
          <div
            class="flex w-full max-w-4xl flex-col rounded-xl bg-n-solid-1 p-5 shadow-xl outline outline-1 outline-n-container"
            role="dialog"
            aria-modal="true"
            :aria-label="t('CONTACT_STATS.DAILY_TREND.TITLE')"
          >
            <div class="mb-4 flex items-center justify-between gap-2">
              <h3 class="text-base font-medium text-n-slate-12">
                {{ t('CONTACT_STATS.DAILY_TREND.TITLE') }}
              </h3>
              <Button
                ghost
                slate
                size="sm"
                icon="i-lucide-x"
                :aria-label="t('CONTACT_STATS.DRAWER.CLOSE')"
                @click="isExpanded = false"
              />
            </div>
            <div class="h-[60vh]">
              <BarChart
                :collection="collection"
                clickable
                @element-click="onElementClick"
              />
            </div>
          </div>
        </div>
      </Transition>
    </TeleportWithDirection>
  </div>
</template>

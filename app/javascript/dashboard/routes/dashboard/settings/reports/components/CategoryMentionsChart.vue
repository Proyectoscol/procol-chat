<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import eachDayOfInterval from 'date-fns/eachDayOfInterval';
import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';
import { colorForIndex } from 'dashboard/helper/auditoriaCategoryPalette';

const props = defineProps({
  series: { type: Array, default: () => [] },
  since: { type: Number, required: true },
  until: { type: Number, required: true },
});

const { t } = useI18n();

const WIDTH = 760;
const HEIGHT = 280;
const MARGIN = { top: 16, right: 16, bottom: 28, left: 36 };
const PLOT_WIDTH = WIDTH - MARGIN.left - MARGIN.right;
const PLOT_HEIGHT = HEIGHT - MARGIN.top - MARGIN.bottom;

const days = computed(() => {
  if (!props.since || !props.until) return [];
  return eachDayOfInterval({
    start: fromUnixTime(props.since),
    end: fromUnixTime(props.until),
  }).map(d => format(d, 'yyyy-MM-dd'));
});

// occurred_on ya viene resuelto por el backend (mensaje real para palabra
// clave, dia reportado por la IA para categorias :ai) -- un dia sin
// mencion es un 0 real, no un hueco: se rellena explicito para que la
// linea refleje el conteo real dia por dia, no interpole sobre dias sin
// datos.
const filledSeries = computed(() =>
  props.series.map((s, index) => {
    const countByDate = Object.fromEntries(
      s.points.map(p => [p.date, p.count])
    );
    return {
      id: s.id,
      title: s.title,
      color: colorForIndex(index),
      counts: days.value.map(date => countByDate[date] || 0),
    };
  })
);

const hasData = computed(() =>
  filledSeries.value.some(s => s.counts.some(c => c > 0))
);

const maxCount = computed(() => {
  const raw = Math.max(1, ...filledSeries.value.flatMap(s => s.counts));
  return raw;
});

const yTicks = computed(() => {
  const step = maxCount.value / 4;
  return [0, 1, 2, 3, 4].map(i => Math.round(step * i));
});

const xForIndex = index =>
  days.value.length <= 1
    ? MARGIN.left
    : MARGIN.left + (index / (days.value.length - 1)) * PLOT_WIDTH;

const yForCount = count =>
  MARGIN.top + PLOT_HEIGHT - (count / maxCount.value) * PLOT_HEIGHT;

const linePath = series =>
  series.counts
    .map(
      (count, index) =>
        `${index === 0 ? 'M' : 'L'}${xForIndex(index)},${yForCount(count)}`
    )
    .join(' ');

const hoverIndex = ref(null);
const svgRef = ref(null);

const onPointerMove = event => {
  if (!svgRef.value || !days.value.length) return;

  const rect = svgRef.value.getBoundingClientRect();
  const relativeX = ((event.clientX - rect.left) / rect.width) * WIDTH;
  const ratio = Math.min(
    1,
    Math.max(0, (relativeX - MARGIN.left) / PLOT_WIDTH)
  );
  hoverIndex.value = Math.round(ratio * (days.value.length - 1));
};
const onPointerLeave = () => {
  hoverIndex.value = null;
};

const hoverDateLabel = computed(() => {
  if (hoverIndex.value === null || !days.value[hoverIndex.value]) return '';
  return format(new Date(days.value[hoverIndex.value]), 'd MMM yyyy');
});

const hoverTooltipX = computed(() => {
  if (hoverIndex.value === null) return 0;
  const x = xForIndex(hoverIndex.value);
  // Evita que el tooltip se salga del viewBox cerca del borde derecho.
  return Math.min(x, WIDTH - MARGIN.right - 140);
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-if="!hasData"
      class="flex h-40 items-center justify-center text-sm text-n-slate-10"
    >
      {{ t('AUDITORIA_CATEGORY_REPORTS.CHART.EMPTY') }}
    </div>

    <svg
      v-else
      ref="svgRef"
      :viewBox="`0 0 ${WIDTH} ${HEIGHT}`"
      class="w-full h-auto"
      role="img"
      @pointermove="onPointerMove"
      @pointerleave="onPointerLeave"
    >
      <!-- grilla + eje Y: recesiva, tokens n-slate ya dark-aware -->
      <g>
        <line
          v-for="tick in yTicks"
          :key="tick"
          :x1="MARGIN.left"
          :x2="WIDTH - MARGIN.right"
          :y1="yForCount(tick)"
          :y2="yForCount(tick)"
          class="stroke-n-weak"
          stroke-width="1"
        />
        <text
          v-for="tick in yTicks"
          :key="`label-${tick}`"
          :x="MARGIN.left - 8"
          :y="yForCount(tick)"
          text-anchor="end"
          dominant-baseline="middle"
          class="fill-n-slate-10 text-[10px]"
        >
          {{ tick }}
        </text>
      </g>

      <!-- una linea por categoria, 2px, color categorico fijo -->
      <path
        v-for="s in filledSeries"
        :key="s.id"
        :d="linePath(s)"
        fill="none"
        stroke-width="2"
        class="[stroke:var(--series-light)] dark:[stroke:var(--series-dark)]"
        :style="{
          '--series-light': s.color.light,
          '--series-dark': s.color.dark,
        }"
      />

      <!-- crosshair + tooltip al pasar el mouse -->
      <g v-if="hoverIndex !== null">
        <line
          :x1="xForIndex(hoverIndex)"
          :x2="xForIndex(hoverIndex)"
          :y1="MARGIN.top"
          :y2="MARGIN.top + PLOT_HEIGHT"
          class="stroke-n-slate-7"
          stroke-width="1"
        />
        <circle
          v-for="s in filledSeries"
          :key="`dot-${s.id}`"
          :cx="xForIndex(hoverIndex)"
          :cy="yForCount(s.counts[hoverIndex])"
          r="3"
          :style="{
            '--series-light': s.color.light,
            '--series-dark': s.color.dark,
          }"
          class="[fill:var(--series-light)] dark:[fill:var(--series-dark)]"
        />
        <foreignObject
          :x="hoverTooltipX"
          :y="MARGIN.top"
          width="140"
          height="100"
        >
          <div
            class="rounded-md bg-n-solid-2 outline outline-1 outline-n-weak px-2 py-1.5 text-[11px] shadow-md"
          >
            <p class="font-medium text-n-slate-12 mb-1">{{ hoverDateLabel }}</p>
            <p
              v-for="s in filledSeries"
              :key="`tooltip-${s.id}`"
              class="flex items-center justify-between gap-2 text-n-slate-11"
            >
              <span class="truncate">{{ s.title }}</span>
              <span class="text-n-slate-12">{{ s.counts[hoverIndex] }}</span>
            </p>
          </div>
        </foreignObject>
      </g>
    </svg>

    <!--
      Leyenda SIEMPRE visible (incluso con 1 sola serie) debajo de la
      grafica -- el color de cada linea no es deducible sin esto, y con
      una sola categoria igual ayuda a confirmar que color le corresponde.
    -->
    <div v-if="hasData" class="flex flex-wrap items-center gap-4" role="list">
      <span
        v-for="s in filledSeries"
        :key="s.id"
        class="flex items-center gap-1.5 text-xs text-n-slate-11"
      >
        <span
          class="size-2.5 rounded-full [background-color:var(--series-light)] dark:[background-color:var(--series-dark)]"
          :style="{
            '--series-light': s.color.light,
            '--series-dark': s.color.dark,
          }"
        />
        {{ s.title }}
      </span>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import eachDayOfInterval from 'date-fns/eachDayOfInterval';
import eachWeekOfInterval from 'date-fns/eachWeekOfInterval';
import eachMonthOfInterval from 'date-fns/eachMonthOfInterval';
import endOfWeek from 'date-fns/endOfWeek';
import endOfMonth from 'date-fns/endOfMonth';
import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';

const props = defineProps({
  series: { type: Array, default: () => [] },
  since: { type: Number, required: true },
  until: { type: Number, required: true },
  bucket: { type: String, default: 'day' },
});

const emit = defineEmits(['selectBucket']);

const { t } = useI18n();

// Mismos hex ya usados en AUDITORIA_CATEGORY_PALETTE (indices 2 y 7, verde
// y rojo) -- no una paleta nueva, para que el lenguaje visual de "positivo/
// negativo" calce con el resto del modulo de Auditoria. 3 series FIJAS (a
// diferencia de categorias, que son dinamicas) -- el orden y color de cada
// una nunca cambia segun que datos haya.
const SENTIMENT_COLORS = {
  positive: { light: '#1baf7a', dark: '#199e70' },
  neutral: { light: '#94a3b8', dark: '#94a3b8' },
  negative: { light: '#e34948', dark: '#e66767' },
};

// Cada rama llama a t() con una clave literal a proposito (regla
// no-dynamic-keys) -- el lookup por sentiment pasa por el objeto, nunca
// por una clave armada en runtime.
const SENTIMENT_LABELS = {
  positive: () => t('AUDITORIA_SENTIMENT_REPORTS.CHART.SENTIMENT.POSITIVE'),
  neutral: () => t('AUDITORIA_SENTIMENT_REPORTS.CHART.SENTIMENT.NEUTRAL'),
  negative: () => t('AUDITORIA_SENTIMENT_REPORTS.CHART.SENTIMENT.NEGATIVE'),
};
const sentimentLabel = sentiment =>
  SENTIMENT_LABELS[sentiment]?.() || sentiment;

const WIDTH = 760;
const HEIGHT = 280;
const MARGIN = { top: 16, right: 16, bottom: 28, left: 36 };
const PLOT_WIDTH = WIDTH - MARGIN.left - MARGIN.right;
const PLOT_HEIGHT = HEIGHT - MARGIN.top - MARGIN.bottom;
const MAX_X_LABELS = 8;

// Cada bucket es el INICIO del periodo (dia, lunes de esa semana, o 1ro de
// mes) -- weekStartsOn: 1 calza con como Postgres date_trunc('week', ...)
// trunca (siempre al lunes, ISO 8601), ver el builder en el backend. Se
// guarda el Date original junto a su key -- volver a parsear la key con
// `new Date(str)` en otro punto del componente (xLabels, hoverDateLabel,
// onChartClick) interpretaria el string como medianoche UTC, no local, y
// en cualquier huso horario detras de UTC (ej. Colombia) eso corre la
// fecha mostrada/clicada un dia hacia atras frente a los datos reales.
const buckets = computed(() => {
  if (!props.since || !props.until) return [];

  const interval = {
    start: fromUnixTime(props.since),
    end: fromUnixTime(props.until),
  };
  const dates =
    {
      week: () => eachWeekOfInterval(interval, { weekStartsOn: 1 }),
      month: () => eachMonthOfInterval(interval),
    }[props.bucket]?.() || eachDayOfInterval(interval);

  return dates.map(date => ({ date, key: format(date, 'yyyy-MM-dd') }));
});

// Un bucket sin conversaciones de ese sentimiento es un 0 real, no un
// hueco: se rellena explicito para que la linea refleje el conteo real
// bucket por bucket, no interpole sobre buckets sin datos.
const filledSeries = computed(() =>
  props.series.map(s => {
    const countByDate = Object.fromEntries(
      s.points.map(p => [p.date, p.count])
    );
    return {
      sentiment: s.sentiment,
      title: sentimentLabel(s.sentiment),
      color: SENTIMENT_COLORS[s.sentiment] || SENTIMENT_COLORS.neutral,
      counts: buckets.value.map(bucket => countByDate[bucket.key] || 0),
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
  buckets.value.length <= 1
    ? MARGIN.left
    : MARGIN.left + (index / (buckets.value.length - 1)) * PLOT_WIDTH;

// Maximo MAX_X_LABELS etiquetas sin importar cuantos buckets haya (hasta
// ~36 en modo dia, ~26 en modo semana) -- muestra el primero, el ultimo, y
// el resto espaciado parejo para que nunca se amontonen.
const xLabelFormat = computed(() =>
  props.bucket === 'month' ? 'MMM yyyy' : 'd MMM'
);
const xLabels = computed(() => {
  const total = buckets.value.length;
  if (!total) return [];

  const step = Math.max(1, Math.ceil(total / MAX_X_LABELS));
  const indices = [];
  for (let index = 0; index < total; index += step) indices.push(index);
  if (indices[indices.length - 1] !== total - 1) indices.push(total - 1);

  return indices.map(index => ({
    index,
    x: xForIndex(index),
    label: format(buckets.value[index].date, xLabelFormat.value),
  }));
});

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

const indexForEvent = event => {
  if (!svgRef.value || !buckets.value.length) return null;

  const rect = svgRef.value.getBoundingClientRect();
  const relativeX = ((event.clientX - rect.left) / rect.width) * WIDTH;
  const ratio = Math.min(
    1,
    Math.max(0, (relativeX - MARGIN.left) / PLOT_WIDTH)
  );
  return Math.round(ratio * (buckets.value.length - 1));
};

const onPointerMove = event => {
  hoverIndex.value = indexForEvent(event);
};
const onPointerLeave = () => {
  hoverIndex.value = null;
};

// Fin del bucket clicado -- dia: el mismo dia; semana/mes: el ultimo dia de
// esa semana/mes (mismo weekStartsOn: 1 que ya usa `buckets`, para calzar
// con como Postgres date_trunc('week', ...) trunca en el backend).
const bucketEndDate = start => {
  if (props.bucket === 'week') return endOfWeek(start, { weekStartsOn: 1 });
  if (props.bucket === 'month') return endOfMonth(start);
  return start;
};

const onChartClick = event => {
  const index = indexForEvent(event);
  if (index === null || !buckets.value[index]) return;

  const start = buckets.value[index].date;
  // El desglose por sentimiento de ESTE bucket exacto viaja con el evento --
  // el padre lo usa para explicar en el drawer "cuantas de cada" antes de
  // que termine de cargar la lista, en vez de dejar al usuario adivinar si
  // el total del drawer calza con lo que vio en el tooltip.
  const counts = Object.fromEntries(
    filledSeries.value.map(s => [s.sentiment, s.counts[index]])
  );
  emit('selectBucket', {
    since: getUnixStartOfDay(start),
    until: getUnixEndOfDay(bucketEndDate(start)),
    counts,
  });
};

const hoverDateLabel = computed(() => {
  if (hoverIndex.value === null || !buckets.value[hoverIndex.value]) return '';
  return format(buckets.value[hoverIndex.value].date, 'd MMM yyyy');
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
      {{ t('AUDITORIA_SENTIMENT_REPORTS.CHART.EMPTY') }}
    </div>

    <svg
      v-else
      ref="svgRef"
      :viewBox="`0 0 ${WIDTH} ${HEIGHT}`"
      class="w-full h-auto cursor-pointer"
      role="img"
      @pointermove="onPointerMove"
      @pointerleave="onPointerLeave"
      @click="onChartClick"
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

      <!-- eje X: fechas de calendario, maximo MAX_X_LABELS para no saturar -->
      <g>
        <text
          v-for="label in xLabels"
          :key="`xlabel-${label.index}`"
          :x="label.x"
          :y="HEIGHT - MARGIN.bottom + 14"
          text-anchor="middle"
          class="fill-n-slate-10 text-[10px]"
        >
          {{ label.label }}
        </text>
      </g>

      <!-- una linea por sentimiento, 2px, color fijo (verde/gris/rojo) -->
      <path
        v-for="s in filledSeries"
        :key="s.sentiment"
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
          :key="`dot-${s.sentiment}`"
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
              :key="`tooltip-${s.sentiment}`"
              class="flex items-center justify-between gap-2 text-n-slate-11"
            >
              <span class="truncate">{{ s.title }}</span>
              <span class="text-n-slate-12">{{ s.counts[hoverIndex] }}</span>
            </p>
          </div>
        </foreignObject>
      </g>
    </svg>

    <!-- Leyenda SIEMPRE visible -- el color de cada linea no es deducible sin esto. -->
    <div v-if="hasData" class="flex flex-wrap items-center gap-4" role="list">
      <span
        v-for="s in filledSeries"
        :key="s.sentiment"
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

    <p v-if="hasData" class="text-xs text-n-slate-10">
      {{ t('AUDITORIA_SENTIMENT_REPORTS.CHART.CLICK_HINT') }}
    </p>
  </div>
</template>

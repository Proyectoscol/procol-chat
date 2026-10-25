<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { colorForIndex } from 'dashboard/helper/auditoriaCategoryPalette';

const props = defineProps({
  // [{ id, title, count }] -- el conteo de cada subcategoria, ya calculado
  // por el padre (mismos numeros que se ven en las filas, sin pedirle
  // nada nuevo al backend).
  segments: { type: Array, default: () => [] },
});

const { t } = useI18n();

const SIZE = 120;
const RADIUS = SIZE / 2;
const STROKE = 22;
const INNER_RADIUS = RADIUS - STROKE / 2;
const CIRCUMFERENCE = 2 * Math.PI * INNER_RADIUS;

const total = computed(() =>
  props.segments.reduce((sum, segment) => sum + segment.count, 0)
);

// De mayor a menor -- mas facil de leer el gajo/fila mas grande primero,
// tanto aqui (distribucion general) como al reusar este componente para
// las subcategorias de una categoria padre expandida.
const sortedSegments = computed(() =>
  [...props.segments].sort((a, b) => b.count - a.count)
);

// stroke-dasharray/offset sobre un circulo: tecnica estandar de donut en
// SVG puro, sin libreria -- cada gajo es un tramo "encendido" seguido del
// resto "apagado", rotados en cadena para que no se superpongan.
const arcs = computed(() => {
  let offset = 0;
  return sortedSegments.value.map((segment, index) => {
    const fraction = total.value ? segment.count / total.value : 0;
    const length = fraction * CIRCUMFERENCE;
    const arc = {
      id: segment.id,
      title: segment.title,
      count: segment.count,
      color: colorForIndex(index),
      dasharray: `${length} ${CIRCUMFERENCE - length}`,
      dashoffset: -offset,
    };
    offset += length;
    return arc;
  });
});
</script>

<template>
  <div class="flex items-center gap-4">
    <template v-if="total">
      <svg
        :viewBox="`0 0 ${SIZE} ${SIZE}`"
        :width="SIZE"
        :height="SIZE"
        role="img"
      >
        <circle
          v-for="arc in arcs"
          :key="arc.id"
          :cx="RADIUS"
          :cy="RADIUS"
          :r="INNER_RADIUS"
          fill="none"
          :stroke-width="STROKE"
          :stroke-dasharray="arc.dasharray"
          :stroke-dashoffset="arc.dashoffset"
          :style="{
            '--seg-light': arc.color.light,
            '--seg-dark': arc.color.dark,
          }"
          class="[stroke:var(--seg-light)] dark:[stroke:var(--seg-dark)]"
          :transform="`rotate(-90 ${RADIUS} ${RADIUS})`"
        />
      </svg>
      <ul class="flex flex-col gap-1">
        <li
          v-for="arc in arcs"
          :key="`legend-${arc.id}`"
          class="flex items-center gap-1.5 text-xs text-n-slate-11"
        >
          <span
            :style="{
              '--seg-light': arc.color.light,
              '--seg-dark': arc.color.dark,
            }"
            class="size-2.5 rounded-full [background-color:var(--seg-light)] dark:[background-color:var(--seg-dark)]"
          />
          {{
            t('AUDITORIA_CATEGORY_REPORTS.TABLE.BREAKDOWN_SEGMENT', {
              title: arc.title,
              count: arc.count,
            })
          }}
        </li>
      </ul>
    </template>
    <p v-else class="text-sm text-n-slate-10">
      {{ t('AUDITORIA_CATEGORY_REPORTS.CHART.EMPTY') }}
    </p>
  </div>
</template>

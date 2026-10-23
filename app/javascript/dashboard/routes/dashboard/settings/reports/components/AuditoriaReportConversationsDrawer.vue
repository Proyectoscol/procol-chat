<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ReportDrilldownCard from './ReportDrilldownCard.vue';
import { useReportDrilldown } from '../composables/useReportDrilldown';

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  description: { type: String, default: '' },
  emptyText: { type: String, default: '' },
  errorText: { type: String, default: '' },
  responseBreakdown: { type: Array, default: () => [] },
  showBreakdown: { type: Boolean, default: false },
  filterParams: { type: Object, default: () => ({}) },
  fetcher: { type: Function, required: true },
  sortableByReason: { type: Boolean, default: false },
  // Opcional -- solo el reporte de Categorias lo pasa hoy. Cuando esta
  // presente, el padre hace la descarga real (axios + downloadCsvFile);
  // el drawer se queda generico, sin saber nada de CSV.
  exportCsv: { type: Function, default: null },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const panelRef = ref(null);

// Funciona igual con claves numericas (1-4) y la clave string "5+" --
// el acceso a objeto en JS normaliza ambas a lookup por clave.
const ORDER_LABEL_KEYS = {
  1: 'ORDER_1',
  2: 'ORDER_2',
  3: 'ORDER_3',
  4: 'ORDER_4',
  '5+': 'ORDER_5_PLUS',
};
const orderLabel = order =>
  t(
    `AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.BREAKDOWN.${ORDER_LABEL_KEYS[order] || 'ORDER_5_PLUS'}`
  );

const {
  records,
  meta,
  isFetching,
  isFetchingMore,
  hasError,
  hasRecords,
  hasMore,
  open: openDrilldown,
  close,
  loadMore,
} = useReportDrilldown(props.fetcher);

const recordKey = record => record.conversation?.id;

// Orden por palabra clave: alcance de solo las filas YA cargadas en la
// pagina actual (no un sort de backend sobre todo el historico) -- mismo
// criterio ya usado para el orden alfabetico del resumen diario por asesor.
const sortBy = ref('default');
const reasonSortKey = record => (record.match_reasons || []).join(', ');
const displayedRecords = computed(() => {
  if (sortBy.value !== 'reason') return records.value;

  return [...records.value].sort((a, b) =>
    reasonSortKey(a).localeCompare(reasonSortKey(b))
  );
});

const fetchConversations = () => {
  sortBy.value = 'default';
  openDrilldown({ ...props.filterParams });
};

const isExportingCsv = ref(false);
const onExportCsv = async () => {
  if (!props.exportCsv) return;

  isExportingCsv.value = true;
  try {
    await props.exportCsv({ ...props.filterParams });
  } finally {
    isExportingCsv.value = false;
  }
};

watch(
  () => props.open,
  isDrawerOpen => {
    if (!isDrawerOpen) {
      panelRef.value?.close();
      close();
      return;
    }

    panelRef.value?.open();
    fetchConversations();
  }
);
</script>

<template>
  <SidePanel
    ref="panelRef"
    :title="title"
    :description="description"
    width="xl"
    @close="emit('close')"
  >
    <template v-if="showBreakdown">
      <div
        v-if="responseBreakdown.length"
        class="mb-4 rounded-lg border border-n-weak p-3"
      >
        <p class="text-sm font-medium text-n-slate-12 mb-2">
          {{
            t('AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.BREAKDOWN.TITLE')
          }}
        </p>
        <ul class="flex flex-col gap-1">
          <li
            v-for="row in responseBreakdown"
            :key="row.order"
            class="flex items-center justify-between text-sm"
          >
            <span class="text-n-slate-11">{{ orderLabel(row.order) }}</span>
            <span class="text-n-slate-12">
              {{ formatTime(row.avgResponseTimeSeconds) }}
              <span class="text-n-slate-10">
                {{
                  t(
                    'AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.BREAKDOWN.COUNT',
                    { count: row.count }
                  )
                }}
              </span>
            </span>
          </li>
        </ul>
      </div>
      <div v-else class="mb-4 text-sm text-n-slate-10">
        {{
          t('AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.BREAKDOWN.EMPTY')
        }}
      </div>
    </template>

    <div v-if="isFetching" class="flex h-40 items-center justify-center">
      <Spinner />
    </div>

    <div
      v-else-if="hasError"
      class="flex h-40 items-center justify-center text-sm text-n-ruby-11"
    >
      {{ errorText }}
    </div>

    <div
      v-else-if="!hasRecords"
      class="flex h-40 items-center justify-center text-sm text-n-slate-10"
    >
      {{ emptyText }}
    </div>

    <div v-else class="flex flex-col gap-2">
      <div class="flex items-center justify-between gap-2 mb-1">
        <p class="text-sm text-n-slate-11">
          {{
            t('REPORT.DRILLDOWN.RESULT_COUNT_CONVERSATION', {
              count: meta.total_count,
            })
          }}
        </p>
        <div class="flex items-center gap-2">
          <template v-if="sortableByReason">
            <label
              for="drilldown-sort-by-reason"
              class="text-xs text-n-slate-10"
            >
              {{ t('REPORT.DRILLDOWN.SORT_LABEL') }}
            </label>
            <select
              id="drilldown-sort-by-reason"
              v-model="sortBy"
              class="reset-base !mb-0 !w-auto text-xs"
            >
              <option value="default">
                {{ t('REPORT.DRILLDOWN.SORT_DEFAULT') }}
              </option>
              <option value="reason">
                {{ t('REPORT.DRILLDOWN.SORT_BY_REASON') }}
              </option>
            </select>
          </template>
          <Button
            v-if="exportCsv"
            faded
            slate
            size="sm"
            icon="i-ph-download-simple"
            :label="t('REPORT.DRILLDOWN.EXPORT_CSV')"
            :is-loading="isExportingCsv"
            @click="onExportCsv"
          />
        </div>
      </div>
      <ReportDrilldownCard
        v-for="record in displayedRecords"
        :key="recordKey(record)"
        :record="record"
      />

      <Button
        v-if="hasMore"
        faded
        slate
        size="sm"
        class="mx-auto mt-2"
        :label="t('REPORT.DRILLDOWN.LOAD_MORE')"
        :is-loading="isFetchingMore"
        @click="loadMore"
      />
    </div>
  </SidePanel>
</template>

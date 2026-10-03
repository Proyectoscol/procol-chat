<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import facturaAPI from 'dashboard/api/cartera/facturas';
import { formatearCop, formatearFecha } from '../cartera-shared/format';

const { t } = useI18n();

const headers = [
  t('CARTERA.FACTURAS.HEADERS.NUMERO'),
  t('CARTERA.FACTURAS.HEADERS.CLIENTE'),
  t('CARTERA.FACTURAS.HEADERS.FECHA_VENCIMIENTO'),
  t('CARTERA.FACTURAS.HEADERS.DIAS_VENCIDOS'),
  t('CARTERA.FACTURAS.HEADERS.VALOR_TOTAL'),
  t('CARTERA.FACTURAS.HEADERS.SALDO_PENDIENTE'),
  t('CARTERA.FACTURAS.HEADERS.TRAMO'),
  t('CARTERA.FACTURAS.HEADERS.ESTADO'),
];

const TRAMOS = [
  'vigente',
  'd1_30',
  'd31_60',
  'd61_90',
  'd91_180',
  'd181_360',
  'mas_360',
];

const items = ref([]);
const page = ref(1);
const total = ref(0);
const pageSize = ref(20);
const isFetching = ref(false);
const tramoSeleccionado = ref('');
const estadoSeleccionado = ref('');

const tramoOptions = computed(() => [
  { value: '', label: t('CARTERA.FACTURAS.FILTER_TRAMO_ALL') },
  ...TRAMOS.map(tramo => ({
    value: tramo,
    label: t(`CARTERA.TRAMOS.${tramo.toUpperCase()}`),
  })),
]);

const estadoOptions = computed(() => [
  { value: '', label: t('CARTERA.FACTURAS.FILTER_ESTADO_ALL') },
  { value: 'abiertas', label: t('CARTERA.FACTURAS.FILTER_ESTADO_ABIERTAS') },
  { value: 'pagadas', label: t('CARTERA.FACTURAS.FILTER_ESTADO_PAGADAS') },
]);

const fetchFacturas = async () => {
  isFetching.value = true;
  try {
    const { data } = await facturaAPI.get({
      page: page.value,
      tramo: tramoSeleccionado.value,
      estado: estadoSeleccionado.value,
    });
    items.value = data.items;
    total.value = data.total;
    pageSize.value = data.page_size;
  } finally {
    isFetching.value = false;
  }
};

watch([tramoSeleccionado, estadoSeleccionado], () => {
  page.value = 1;
  fetchFacturas();
});

const goToPage = newPage => {
  if (newPage < 1 || newPage > Math.ceil(total.value / pageSize.value)) return;
  page.value = newPage;
  fetchFacturas();
};

onMounted(fetchFacturas);
</script>

<template>
  <div class="flex flex-col flex-1 h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex items-center justify-between gap-3 px-6 py-3 border-b border-n-weak flex-shrink-0"
    >
      <div class="flex items-center gap-3">
        <span class="i-lucide-receipt size-5 text-n-slate-11" />
        <h1 class="text-base font-semibold text-n-slate-12">
          {{ t('CARTERA.FACTURAS.TITLE') }}
        </h1>
      </div>
      <div class="flex items-center gap-2">
        <Select v-model="estadoSeleccionado" :options="estadoOptions" />
        <Select v-model="tramoSeleccionado" :options="tramoOptions" />
      </div>
    </header>

    <div class="flex-1 overflow-y-auto p-6">
      <BaseTable
        :headers="headers"
        :items="items"
        :loading="isFetching"
        :no-data-message="t('CARTERA.FACTURAS.EMPTY_STATE')"
      >
        <template #row="{ items: rows }">
          <BaseTableRow
            v-for="factura in rows"
            :key="factura.factura_id"
            :item="factura"
          >
            <template #default>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12 whitespace-nowrap">
                  {{ factura.numero }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12 truncate">
                  {{ factura.nombre_cliente }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11 whitespace-nowrap">
                  {{ formatearFecha(factura.fecha_vencimiento) }}
                </span>
              </BaseTableCell>
              <BaseTableCell align="center">
                <span class="text-body-main text-n-slate-11">
                  {{ factura.dias_vencidos }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12 whitespace-nowrap">
                  {{ formatearCop(factura.valor_total) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12 whitespace-nowrap">
                  {{ formatearCop(factura.saldo_pendiente) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span
                  class="text-body-main text-n-slate-11 whitespace-nowrap capitalize"
                >
                  {{ t(`CARTERA.TRAMOS.${factura.tramo.toUpperCase()}`) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span
                  class="rounded-full border px-2 py-0.5 text-[10px] whitespace-nowrap"
                  :class="
                    factura.pagada
                      ? 'border-n-teal-6 bg-n-teal-3 text-n-teal-11'
                      : 'border-n-amber-6 bg-n-amber-3 text-n-amber-11'
                  "
                >
                  {{
                    factura.pagada
                      ? t('CARTERA.FACTURAS.ESTADO_PAGADA')
                      : t('CARTERA.FACTURAS.ESTADO_ABIERTA')
                  }}
                </span>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>

      <div
        v-if="total > pageSize"
        class="flex items-center justify-between mt-4"
      >
        <p class="text-sm text-n-slate-11">
          {{
            t('CARTERA.PAGINATION', {
              page,
              totalPages: Math.ceil(total / pageSize),
            })
          }}
        </p>
        <div class="flex gap-2">
          <Button
            icon="i-lucide-chevron-left"
            ghost
            slate
            sm
            :disabled="page <= 1"
            @click="goToPage(page - 1)"
          />
          <Button
            icon="i-lucide-chevron-right"
            ghost
            slate
            sm
            :disabled="page >= Math.ceil(total / pageSize)"
            @click="goToPage(page + 1)"
          />
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import { formatearCop, formatearFecha } from './format';

const props = defineProps({
  items: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  emptyMessage: { type: String, default: '' },
  hideClienteColumn: { type: Boolean, default: false },
});

const { t } = useI18n();

const headers = computed(() =>
  [
    t('CARTERA.FACTURAS.HEADERS.NUMERO'),
    !props.hideClienteColumn && t('CARTERA.FACTURAS.HEADERS.CLIENTE'),
    t('CARTERA.FACTURAS.HEADERS.FECHA_VENCIMIENTO'),
    t('CARTERA.FACTURAS.HEADERS.DIAS_VENCIDOS'),
    t('CARTERA.FACTURAS.HEADERS.VALOR_TOTAL'),
    t('CARTERA.FACTURAS.HEADERS.SALDO_PENDIENTE'),
    t('CARTERA.FACTURAS.HEADERS.TRAMO'),
    t('CARTERA.FACTURAS.HEADERS.ESTADO'),
  ].filter(Boolean)
);
</script>

<template>
  <BaseTable
    :headers="headers"
    :items="items"
    :loading="loading"
    :no-data-message="emptyMessage"
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
          <BaseTableCell v-if="!hideClienteColumn">
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
</template>

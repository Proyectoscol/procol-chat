<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useVueTable, getCoreRowModel } from '@tanstack/vue-table';
import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import TableCard from './TableCard.vue';
import ClickableTable from './ClickableTable.vue';
import { buildFacturasColumns } from './facturasColumns';

const props = defineProps({
  items: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  emptyMessage: { type: String, default: '' },
  hideClienteColumn: { type: Boolean, default: false },
});

const { t } = useI18n();
const router = useRouter();

const abrirFicha = factura => {
  router.push({
    name: 'cartera_facturas_ficha_view',
    params: { facturaId: factura.factura_id },
  });
};

const columns = computed(() =>
  buildFacturasColumns(t, props.hideClienteColumn)
);

const table = useVueTable({
  get data() {
    return props.items;
  },
  get columns() {
    return columns.value;
  },
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});
</script>

<template>
  <TableCard>
    <ClickableTable :table="table" @row-click="abrirFicha" />
  </TableCard>
  <div
    v-if="loading && !items.length"
    class="flex items-center justify-center py-16"
  >
    <Spinner />
  </div>
  <EmptyState v-else-if="!loading && !items.length" :title="emptyMessage" />
</template>

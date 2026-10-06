<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useVueTable, getCoreRowModel } from '@tanstack/vue-table';
import { useDebounceFn } from '@vueuse/core';
import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import facturaAPI from 'dashboard/api/cartera/facturas';
import clienteAPI from 'dashboard/api/cartera/clientes';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';
import ClickableTable from '../cartera-shared/ClickableTable.vue';
import { buildFacturasColumns } from '../cartera-shared/facturasColumns';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

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
const total = ref(0);
const pageIndex = ref(0);
const pageSize = ref(10);
const isFetching = ref(false);
// Prellenado desde Resumen (ej. click en un tramo de antiguedad) via query params.
const tramoSeleccionado = ref(
  TRAMOS.includes(route.query.tramo) ? route.query.tramo : ''
);
const estadoSeleccionado = ref(
  ['abiertas', 'pagadas'].includes(route.query.estado) ? route.query.estado : ''
);
const numeroBuscado = ref('');
const clienteSeleccionado = ref(null);
const sorting = ref([]);

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

const sortDirDe = columnaOrden => {
  if (!columnaOrden) return undefined;
  return columnaOrden.desc ? 'desc' : 'asc';
};

const fetchFacturas = async () => {
  isFetching.value = true;
  try {
    const columnaOrden = sorting.value[0];
    const { data } = await facturaAPI.get({
      page: pageIndex.value + 1,
      pageSize: pageSize.value,
      tramo: tramoSeleccionado.value,
      estado: estadoSeleccionado.value,
      numero: numeroBuscado.value,
      clienteId: clienteSeleccionado.value?.id,
      sortBy: columnaOrden?.id,
      sortDir: sortDirDe(columnaOrden),
    });
    items.value = data.items;
    total.value = data.total;
  } finally {
    isFetching.value = false;
  }
};

watch(
  [tramoSeleccionado, estadoSeleccionado, numeroBuscado, clienteSeleccionado],
  () => {
    pageIndex.value = 0;
    fetchFacturas();
  }
);

const columns = computed(() => buildFacturasColumns(t));

const exportUrl = computed(() =>
  facturaAPI.exportUrl({
    tramo: tramoSeleccionado.value,
    estado: estadoSeleccionado.value,
    numero: numeroBuscado.value,
    clienteId: clienteSeleccionado.value?.id,
  })
);

const paginationState = computed(() => ({
  pageIndex: pageIndex.value,
  pageSize: pageSize.value,
}));
const sortingState = computed(() => sorting.value);

const table = useVueTable({
  get data() {
    return items.value;
  },
  get columns() {
    return columns.value;
  },
  manualPagination: true,
  manualSorting: true,
  enableSorting: true,
  getCoreRowModel: getCoreRowModel(),
  get rowCount() {
    return total.value;
  },
  state: {
    get pagination() {
      return paginationState.value;
    },
    get sorting() {
      return sortingState.value;
    },
  },
  onPaginationChange: updater => {
    const next = updater(paginationState.value);
    pageIndex.value = next.pageIndex;
    pageSize.value = next.pageSize;
    fetchFacturas();
  },
  onSortingChange: updater => {
    sorting.value = updater(sortingState.value);
    pageIndex.value = 0;
    fetchFacturas();
  },
});

const abrirFicha = factura => {
  router.push({
    name: 'cartera_facturas_ficha_view',
    params: { facturaId: factura.factura_id },
  });
};

/* ---------- Buscador de cliente (filtra la tabla, no navega) ---------- */

const searchOptions = ref([]);
const buscarClientes = async query => {
  if (!query) {
    searchOptions.value = [];
    return;
  }
  try {
    const { data } = await clienteAPI.search(query);
    searchOptions.value = data.map(cliente => ({
      value: cliente.cliente_id,
      label: `${cliente.nombre} · ${cliente.identificacion}`,
    }));
  } catch {
    searchOptions.value = [];
  }
};
const handleSearchCliente = useDebounceFn(query => {
  buscarClientes(query?.trim() || '');
}, 300);
const handleSelectCliente = clienteId => {
  if (!clienteId) {
    clienteSeleccionado.value = null;
    return;
  }
  const opcion = searchOptions.value.find(o => o.value === clienteId);
  clienteSeleccionado.value = { id: clienteId, nombre: opcion?.label || '' };
};

onMounted(fetchFacturas);
</script>

<template>
  <div>
    <CarteraHeader :header-title="t('CARTERA.FACTURAS.TITLE')">
      <div class="flex items-center gap-2">
        <ComboBox
          :options="searchOptions"
          :model-value="clienteSeleccionado?.id || ''"
          :display-label="clienteSeleccionado?.nombre"
          :placeholder="t('CARTERA.FACTURAS.BUSCAR_CLIENTE_PLACEHOLDER')"
          :search-placeholder="t('CARTERA.FACTURAS.BUSCAR_CLIENTE_PLACEHOLDER')"
          use-api-results
          class="w-56 [&>div>button]:h-8"
          @search="handleSearchCliente"
          @update:model-value="handleSelectCliente"
        />
        <Input
          v-model="numeroBuscado"
          :placeholder="t('CARTERA.FACTURAS.BUSCAR_NUMERO_PLACEHOLDER')"
          class="w-44 [&>input]:h-8"
        />
        <Select v-model="estadoSeleccionado" :options="estadoOptions" />
        <Select v-model="tramoSeleccionado" :options="tramoOptions" />
        <a :href="exportUrl">
          <Button
            icon="i-lucide-download"
            slate
            faded
            size="sm"
            :label="t('CARTERA.EXPORTAR_CSV')"
          />
        </a>
      </div>
    </CarteraHeader>

    <TableCard>
      <ClickableTable :table="table" @row-click="abrirFicha" />

      <template #footer>
        <Pagination
          :table="table"
          show-page-size-selector
          :default-page-size="pageSize"
        />
      </template>
    </TableCard>

    <div
      v-if="isFetching && !items.length"
      class="flex items-center justify-center py-16"
    >
      <Spinner />
    </div>
    <EmptyState
      v-else-if="!isFetching && !items.length"
      :title="t('CARTERA.FACTURAS.EMPTY_STATE')"
    />
  </div>
</template>

<script setup>
import { ref, computed, h, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';
import { useDebounceFn } from '@vueuse/core';
import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Pagination from 'dashboard/components/table/Pagination.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import clienteAPI from 'dashboard/api/cartera/clientes';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';
import ClickableTable from '../cartera-shared/ClickableTable.vue';
import { formatearCop } from '../cartera-shared/format';

const { t } = useI18n();
const router = useRouter();

const colorTramo = tramo => {
  if (!tramo || tramo === 'vigente') return 'text-n-teal-11';
  if (['d1_30', 'd31_60'].includes(tramo)) return 'text-n-amber-11';
  return 'text-n-ruby-11';
};

const colorPuntajeRiesgo = valor => {
  if (valor === null) return 'text-n-slate-10';
  if (valor >= 70) return 'text-n-ruby-11';
  if (valor >= 40) return 'text-n-slate-12';
  return 'text-n-teal-11';
};

const sinDato = () => t('CARTERA.CLIENTES.SIN_DATO');

const items = ref([]);
const total = ref(0);
const pageIndex = ref(0);
const pageSize = ref(10);
const isFetching = ref(false);
// id de columna del frontend -> sort_by que entiende PriorizacionService#aplicar_orden.
const SORT_BY_POR_COLUMNA = {
  nombre_cliente: 'nombre_deudor',
  identificacion: 'identificacion',
  telefono_clasificado: 'telefono',
  saldo_abierto: 'saldo_abierto',
  tramo: 'dias_vencido_max',
  puntaje_riesgo: 'puntaje_riesgo',
  total_facturado_historico: 'total_facturado_historico',
  facturas_abiertas_cantidad: 'facturas_abiertas_cantidad',
};
const sorting = ref([]);

const sortDirDe = columnaOrden => {
  if (!columnaOrden) return undefined;
  return columnaOrden.desc ? 'desc' : 'asc';
};

const fetchClientes = async () => {
  isFetching.value = true;
  try {
    const columnaOrden = sorting.value[0];
    const { data } = await clienteAPI.get({
      page: pageIndex.value + 1,
      pageSize: pageSize.value,
      sortBy: columnaOrden ? SORT_BY_POR_COLUMNA[columnaOrden.id] : undefined,
      sortDir: sortDirDe(columnaOrden),
    });
    items.value = data.items;
    total.value = data.total;
  } finally {
    isFetching.value = false;
  }
};

const spanCell = (value, className = 'text-body-main text-n-slate-12') =>
  h('span', { class: className }, value);

const columnHelper = createColumnHelper();
const columns = [
  columnHelper.accessor('nombre_cliente', {
    header: t('CARTERA.CLIENTES.HEADERS.CLIENTE'),
    size: 220,
    enableSorting: true,
    cell: cellProps => {
      const cliente = cellProps.row.original;
      return h('div', { class: 'flex items-center gap-2 min-w-0' }, [
        h(
          'span',
          { class: 'text-body-main text-n-slate-12 truncate' },
          cliente.nombre_cliente
        ),
        cliente.no_cobrar
          ? h(
              'span',
              {
                class:
                  'flex-shrink-0 rounded-full border border-n-ruby-6 bg-n-ruby-3 px-2 py-0.5 text-[10px] text-n-ruby-11',
              },
              t('CARTERA.CLIENTES.NO_COBRAR')
            )
          : null,
      ]);
    },
  }),
  columnHelper.accessor('identificacion', {
    header: t('CARTERA.CLIENTES.HEADERS.NIT'),
    size: 120,
    enableSorting: true,
    cell: cellProps =>
      spanCell(
        cellProps.getValue(),
        'text-body-main text-n-slate-11 whitespace-nowrap'
      ),
  }),
  columnHelper.accessor('telefono_clasificado', {
    header: t('CARTERA.CLIENTES.HEADERS.TELEFONO'),
    size: 130,
    enableSorting: true,
    cell: cellProps =>
      spanCell(
        cellProps.getValue()?.numero_para_llamar ?? sinDato(),
        'text-body-main text-n-slate-11 whitespace-nowrap'
      ),
  }),
  columnHelper.accessor('saldo_abierto', {
    header: t('CARTERA.CLIENTES.HEADERS.SALDO_PENDIENTE'),
    size: 140,
    enableSorting: true,
    cell: cellProps =>
      spanCell(
        formatearCop(cellProps.getValue()),
        'text-body-main text-n-slate-12 whitespace-nowrap tabular-nums'
      ),
  }),
  columnHelper.accessor('tramo', {
    header: t('CARTERA.CLIENTES.HEADERS.MORA'),
    size: 140,
    enableSorting: true,
    cell: cellProps => {
      const cliente = cellProps.row.original;
      const label = cliente.tramo
        ? `${t(`CARTERA.TRAMOS.${cliente.tramo.toUpperCase()}`)} (${cliente.dias_vencido_max}d)`
        : sinDato();
      return spanCell(
        label,
        `text-body-main whitespace-nowrap ${colorTramo(cliente.tramo)}`
      );
    },
  }),
  columnHelper.accessor('puntaje_riesgo', {
    header: t('CARTERA.CLIENTES.HEADERS.PUNTAJE_RIESGO'),
    size: 130,
    enableSorting: true,
    cell: cellProps => {
      const valor = cellProps.getValue();
      const label = valor === null ? sinDato() : `${valor}/100`;
      return spanCell(
        label,
        `text-body-main whitespace-nowrap ${colorPuntajeRiesgo(valor)}`
      );
    },
  }),
  columnHelper.accessor('total_facturado_historico', {
    header: t('CARTERA.CLIENTES.HEADERS.TOTAL_FACTURADO'),
    size: 150,
    enableSorting: true,
    cell: cellProps =>
      spanCell(
        formatearCop(cellProps.getValue()),
        'text-body-main text-n-slate-12 whitespace-nowrap tabular-nums'
      ),
  }),
  columnHelper.accessor('facturas_abiertas_cantidad', {
    header: t('CARTERA.CLIENTES.HEADERS.FACTURAS_ABIERTAS'),
    size: 90,
    enableSorting: true,
    cell: cellProps =>
      spanCell(cellProps.getValue(), 'text-body-main text-n-slate-12'),
  }),
];

const paginationState = computed(() => ({
  pageIndex: pageIndex.value,
  pageSize: pageSize.value,
}));
const sortingState = computed(() => sorting.value);

const table = useVueTable({
  get data() {
    return items.value;
  },
  columns,
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
    fetchClientes();
  },
  onSortingChange: updater => {
    sorting.value = updater(sortingState.value);
    pageIndex.value = 0;
    fetchClientes();
  },
});

const abrirFicha = cliente => {
  router.push({
    name: 'cartera_clientes_ficha_view',
    params: { clienteId: cliente.cliente_id },
  });
};

/* ---------- Buscador ---------- */

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
const handleSearch = useDebounceFn(query => {
  buscarClientes(query?.trim() || '');
}, 300);
const handleSelectCliente = clienteId => {
  if (!clienteId) return;
  router.push({
    name: 'cartera_clientes_ficha_view',
    params: { clienteId },
  });
};

onMounted(fetchClientes);
</script>

<template>
  <div>
    <CarteraHeader :header-title="t('CARTERA.CLIENTES.TITLE')">
      <div class="flex items-center gap-2">
        <ComboBox
          :options="searchOptions"
          :placeholder="t('CARTERA.CLIENTES.BUSCAR_PLACEHOLDER')"
          :search-placeholder="t('CARTERA.CLIENTES.BUSCAR_PLACEHOLDER')"
          use-api-results
          class="w-64 [&>div>button]:h-8"
          @search="handleSearch"
          @update:model-value="handleSelectCliente"
        />
        <a :href="clienteAPI.exportUrl()">
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
      :title="t('CARTERA.CLIENTES.EMPTY_STATE')"
    />
  </div>
</template>

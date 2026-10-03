<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import facturaAPI from 'dashboard/api/cartera/facturas';
import FacturasTable from '../cartera-shared/FacturasTable.vue';

const { t } = useI18n();

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

const onPageChange = newPage => {
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
      <FacturasTable
        :items="items"
        :loading="isFetching"
        :empty-message="t('CARTERA.FACTURAS.EMPTY_STATE')"
      />
    </div>

    <PaginationFooter
      v-if="total > pageSize"
      :current-page="page"
      :total-items="total"
      :items-per-page="pageSize"
      @update:current-page="onPageChange"
    />
  </div>
</template>

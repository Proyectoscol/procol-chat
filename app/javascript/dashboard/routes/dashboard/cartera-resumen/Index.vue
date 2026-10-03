<script setup>
import { ref, computed, watch, h, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { BarChart, LineChart } from '@chatwoot/viz';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';
import Spinner from 'shared/components/Spinner.vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import dashboardAPI from 'dashboard/api/cartera/dashboard';
import syncAPI from 'dashboard/api/cartera/syncs';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';
import ClickableTable from '../cartera-shared/ClickableTable.vue';
import MetricCard from '../cartera-shared/MetricCard.vue';
import Panel from '../cartera-shared/Panel.vue';
import { formatearCop } from '../cartera-shared/format';

const { t } = useI18n();
const { isAdmin } = useAdmin();
const router = useRouter();

const isFetching = ref(false);
const isSyncing = ref(false);
const sucursalSeleccionada = ref('');
const sucursales = ref([]);
const resumen = ref(null);
const tendencia = ref(null);
const prescripcion = ref(null);

const sucursalOptions = computed(() => [
  { value: '', label: t('CARTERA.RESUMEN.SUCURSAL_ALL') },
  ...sucursales.value.map(s => ({ value: s, label: s })),
]);

const tramoLabel = tramo => t(`CARTERA.TRAMOS.${tramo.toUpperCase()}`);
const tramoPorVencerLabel = tramo =>
  t(`CARTERA.RESUMEN.TRAMOS_POR_VENCER.${tramo.toUpperCase()}`);

// Los valores en COP (cientos de millones) desbordan el eje del chart si se
// muestran completos - se grafican en millones (con una nota de unidad) y
// la tabla de respaldo debajo sigue mostrando el valor exacto en COP.
const formatearMillones = valor =>
  new Intl.NumberFormat('es-CO', { maximumFractionDigits: 1 }).format(
    Number(valor) / 1_000_000
  );

const agingChartData = computed(() => {
  const tramos = resumen.value?.tramos || [];
  return {
    categories: tramos.map(item => tramoLabel(item.tramo)),
    series: [
      {
        id: 'valor_total',
        label: t('CARTERA.RESUMEN.VALOR_TOTAL'),
        color: 'rgb(var(--ruby-9))',
        data: tramos.map(item => item.valor_total),
      },
    ],
  };
});

const porVencerChartData = computed(() => {
  const tramos = resumen.value?.por_vencer || [];
  return {
    categories: tramos.map(item => tramoPorVencerLabel(item.tramo)),
    series: [
      {
        id: 'valor_total',
        label: t('CARTERA.RESUMEN.VALOR_TOTAL'),
        color: 'rgb(var(--blue-9))',
        data: tramos.map(item => item.valor_total),
      },
    ],
  };
});

const tendenciaChartData = computed(() => {
  const puntos = tendencia.value?.puntos || [];
  return {
    categories: puntos.map(p => p.mes),
    series: [
      {
        id: 'vigente',
        label: t('CARTERA.RESUMEN.TENDENCIA_VIGENTE'),
        color: 'rgb(var(--teal-9))',
        data: puntos.map(p => p.valor_vigente),
      },
      {
        id: 'vencido',
        label: t('CARTERA.RESUMEN.TENDENCIA_VENCIDO'),
        color: 'rgb(var(--ruby-9))',
        data: puntos.map(p => p.valor_vencido),
      },
    ],
  };
});

const hasAgingData = computed(() =>
  (resumen.value?.tramos || []).some(item => item.valor_total > 0)
);
const hasPorVencerData = computed(() =>
  (resumen.value?.por_vencer || []).some(item => item.valor_total > 0)
);
const hasTendenciaData = computed(
  () => (tendencia.value?.puntos || []).length > 0
);
const hasPrescripcionData = computed(() =>
  (prescripcion.value?.tramos || []).some(item => item.cantidad_facturas > 0)
);
const prescripcionConDatos = computed(() =>
  (prescripcion.value?.tramos || []).filter(tr => tr.cantidad_facturas > 0)
);

const facturasVigentesCount = computed(() => {
  const item = (resumen.value?.tramos || []).find(tr => tr.tramo === 'vigente');
  return item?.cantidad_facturas || 0;
});
const facturasVencidasCount = computed(() =>
  (resumen.value?.tramos || [])
    .filter(tr => tr.tramo !== 'vigente')
    .reduce((sum, tr) => sum + tr.cantidad_facturas, 0)
);

const plazoPromedioCobroLabel = computed(() => {
  const dias = resumen.value?.plazo_promedio_cobro_dias;
  if (dias === null || dias === undefined) {
    return t('CARTERA.RESUMEN.PLAZO_PROMEDIO_COBRO_SIN_DATO');
  }
  return t('CARTERA.RESUMEN.PLAZO_PROMEDIO_COBRO_VALOR', {
    dias: Math.round(dias),
  });
});

const fetchResumen = async () => {
  isFetching.value = true;
  try {
    const { data } = await dashboardAPI.get({
      sucursal: sucursalSeleccionada.value,
    });
    resumen.value = data.resumen;
    tendencia.value = data.tendencia;
    prescripcion.value = data.prescripcion;
    sucursales.value = data.sucursales;
  } finally {
    isFetching.value = false;
  }
};

const actualizar = async () => {
  isSyncing.value = true;
  try {
    const { data } = await syncAPI.create();
    if (data.estado === 'fallida') {
      useAlert(t('CARTERA.RESUMEN.SYNC_ERROR'));
    } else {
      useAlert(
        t('CARTERA.RESUMEN.SYNC_SUCCESS', { count: data.registros_procesados })
      );
    }
    await fetchResumen();
  } catch {
    useAlert(t('CARTERA.RESUMEN.SYNC_ERROR'));
  } finally {
    isSyncing.value = false;
  }
};

const verFacturas = query =>
  router.push({ name: 'cartera_facturas_view', query });

const spanCell = (value, className = 'text-body-main text-n-slate-12') =>
  h('span', { class: className }, value);

const columnHelper = createColumnHelper();

const tramoColumns = computed(() => [
  columnHelper.accessor('tramo', {
    header: t('CARTERA.RESUMEN.TABLE_TRAMO'),
    size: 180,
    cell: cellProps => spanCell(tramoLabel(cellProps.getValue())),
  }),
  columnHelper.accessor('cantidad_facturas', {
    header: t('CARTERA.RESUMEN.TABLE_FACTURAS'),
    size: 100,
    cell: cellProps =>
      spanCell(cellProps.getValue(), 'text-body-main text-n-slate-11'),
  }),
  columnHelper.accessor('valor_total', {
    header: t('CARTERA.RESUMEN.TABLE_VALOR'),
    size: 160,
    cell: cellProps =>
      spanCell(
        formatearCop(cellProps.getValue()),
        'text-body-main text-n-slate-12 tabular-nums'
      ),
  }),
]);

const agingTable = useVueTable({
  get data() {
    return resumen.value?.tramos || [];
  },
  get columns() {
    return tramoColumns.value;
  },
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});
const onAgingRowClick = row =>
  verFacturas({ tramo: row.tramo, estado: 'abiertas' });

const porVencerColumns = computed(() => [
  columnHelper.accessor('tramo', {
    header: t('CARTERA.RESUMEN.TABLE_TRAMO'),
    size: 180,
    cell: cellProps => spanCell(tramoPorVencerLabel(cellProps.getValue())),
  }),
  columnHelper.accessor('cantidad_facturas', {
    header: t('CARTERA.RESUMEN.TABLE_FACTURAS'),
    size: 100,
    cell: cellProps =>
      spanCell(cellProps.getValue(), 'text-body-main text-n-slate-11'),
  }),
  columnHelper.accessor('valor_total', {
    header: t('CARTERA.RESUMEN.TABLE_VALOR'),
    size: 160,
    cell: cellProps =>
      spanCell(
        formatearCop(cellProps.getValue()),
        'text-body-main text-n-slate-12 tabular-nums'
      ),
  }),
]);

const porVencerTable = useVueTable({
  get data() {
    return resumen.value?.por_vencer || [];
  },
  get columns() {
    return porVencerColumns.value;
  },
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});
const onPorVencerRowClick = () => verFacturas({ estado: 'abiertas' });

const tendenciaColumns = [
  columnHelper.accessor('mes', {
    header: t('CARTERA.RESUMEN.TABLE_MES'),
    size: 120,
    cell: cellProps => spanCell(cellProps.getValue()),
  }),
  columnHelper.accessor('valor_vigente', {
    header: t('CARTERA.RESUMEN.TABLE_VIGENTE'),
    size: 150,
    cell: cellProps =>
      spanCell(
        formatearCop(cellProps.getValue()),
        'text-body-main text-n-teal-11 tabular-nums'
      ),
  }),
  columnHelper.accessor('valor_vencido', {
    header: t('CARTERA.RESUMEN.TABLE_VENCIDO'),
    size: 150,
    cell: cellProps =>
      spanCell(
        formatearCop(cellProps.getValue()),
        'text-body-main text-n-ruby-11 tabular-nums'
      ),
  }),
];

const tendenciaTable = useVueTable({
  get data() {
    return tendencia.value?.puntos || [];
  },
  columns: tendenciaColumns,
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});

const prescripcionColumns = [
  columnHelper.accessor('tramo', {
    header: t('CARTERA.RESUMEN.PRESCRIPCION_TABLE_VENTANA'),
    size: 180,
    cell: cellProps =>
      spanCell(
        t(
          `CARTERA.RESUMEN.PRESCRIPCION_VENTANAS.${cellProps.getValue().toUpperCase()}`
        ),
        'text-body-main text-n-ruby-11'
      ),
  }),
  columnHelper.accessor('cantidad_facturas', {
    header: t('CARTERA.RESUMEN.TABLE_FACTURAS'),
    size: 100,
    cell: cellProps =>
      spanCell(cellProps.getValue(), 'text-body-main text-n-slate-11'),
  }),
  columnHelper.accessor('valor_en_riesgo', {
    header: t('CARTERA.RESUMEN.TABLE_VALOR'),
    size: 160,
    cell: cellProps =>
      spanCell(
        formatearCop(cellProps.getValue()),
        'text-body-main text-n-slate-12 tabular-nums'
      ),
  }),
];

const prescripcionTable = useVueTable({
  get data() {
    return prescripcionConDatos.value;
  },
  columns: prescripcionColumns,
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});

watch(sucursalSeleccionada, fetchResumen);
onMounted(fetchResumen);
</script>

<template>
  <div>
    <CarteraHeader :header-title="t('CARTERA.RESUMEN.TITLE')">
      <div class="flex items-center gap-2">
        <Select
          v-if="sucursales.length"
          v-model="sucursalSeleccionada"
          :options="sucursalOptions"
        />
        <Button
          v-if="isAdmin"
          icon="i-lucide-refresh-cw"
          slate
          faded
          size="sm"
          :is-loading="isSyncing"
          :label="t('CARTERA.RESUMEN.SYNC_BUTTON')"
          @click="actualizar"
        />
      </div>
    </CarteraHeader>

    <div
      v-if="isFetching && !resumen"
      class="flex items-center justify-center py-20"
    >
      <Spinner />
    </div>

    <template v-else-if="resumen">
      <div class="grid grid-cols-2 gap-4 mb-4 lg:grid-cols-4">
        <button
          type="button"
          class="text-left"
          @click="verFacturas({ tramo: 'vigente', estado: 'abiertas' })"
        >
          <MetricCard
            :label="t('CARTERA.RESUMEN.VALOR_VIGENTE')"
            :value="formatearCop(resumen.valor_vigente)"
            value-class="text-n-teal-11"
            :subtext="
              t('CARTERA.RESUMEN.FACTURAS_COUNT', {
                count: facturasVigentesCount,
              })
            "
          />
        </button>
        <button
          type="button"
          class="text-left"
          @click="verFacturas({ estado: 'abiertas' })"
        >
          <MetricCard
            :label="t('CARTERA.RESUMEN.VALOR_VENCIDO')"
            :value="formatearCop(resumen.valor_vencido)"
            value-class="text-n-ruby-11"
            :subtext="
              t('CARTERA.RESUMEN.FACTURAS_COUNT', {
                count: facturasVencidasCount,
              })
            "
          />
        </button>
        <MetricCard
          :label="t('CARTERA.RESUMEN.CUPO_TOTAL')"
          :value="formatearCop(resumen.cupo_total)"
        />
        <MetricCard
          :label="t('CARTERA.RESUMEN.CUPO_DISPONIBLE')"
          :value="formatearCop(resumen.cupo_disponible)"
        />
      </div>

      <div class="grid grid-cols-1 gap-4 mb-4 lg:grid-cols-2">
        <Panel :title="t('CARTERA.RESUMEN.AGING_TITLE')">
          <template v-if="hasAgingData">
            <p class="mb-2 text-xs text-n-slate-10">
              {{ t('CARTERA.RESUMEN.VALORES_EN_MILLONES') }}
            </p>
            <div class="h-56">
              <BarChart
                :data="agingChartData"
                :format-value="formatearMillones"
                :height="224"
                :show-values="false"
                :aria-label="t('CARTERA.RESUMEN.AGING_TITLE')"
              />
            </div>
          </template>
          <div
            v-else
            class="grid h-56 text-body-main place-content-center text-n-slate-10"
          >
            {{ t('CARTERA.RESUMEN.AGING_EMPTY', { value: formatearCop(0) }) }}
          </div>

          <TableCard v-if="hasAgingData" class="mt-4">
            <ClickableTable :table="agingTable" @row-click="onAgingRowClick" />
          </TableCard>
        </Panel>

        <Panel :title="t('CARTERA.RESUMEN.TENDENCIA_TITLE')">
          <div v-if="hasTendenciaData" class="h-56">
            <LineChart
              :data="tendenciaChartData"
              :format-value="formatearMillones"
              :height="224"
              :point-radius="2"
              :show-values="false"
              :y-tick-count="4"
              :aria-label="t('CARTERA.RESUMEN.TENDENCIA_TITLE')"
            />
          </div>
          <div
            v-else
            class="grid h-56 text-body-main place-content-center text-n-slate-10"
          >
            {{ t('CARTERA.RESUMEN.PRESCRIPCION_EMPTY') }}
          </div>

          <TableCard v-if="hasTendenciaData" class="mt-4">
            <ClickableTable :table="tendenciaTable" :clickable="false" />
          </TableCard>
        </Panel>
      </div>

      <Panel class="mb-4" :title="t('CARTERA.RESUMEN.POR_VENCER_TITLE')">
        <template #actions>
          <span class="text-xs text-n-slate-10">
            {{
              t('CARTERA.RESUMEN.PLAZO_PROMEDIO_COBRO_LINE', {
                value: plazoPromedioCobroLabel,
              })
            }}
          </span>
        </template>
        <template v-if="hasPorVencerData">
          <p class="mb-2 text-xs text-n-slate-10">
            {{ t('CARTERA.RESUMEN.VALORES_EN_MILLONES') }}
          </p>
          <div class="h-56">
            <BarChart
              :data="porVencerChartData"
              :format-value="formatearMillones"
              :height="224"
              :show-values="false"
              :aria-label="t('CARTERA.RESUMEN.POR_VENCER_TITLE')"
            />
          </div>
        </template>
        <p
          v-else
          class="grid h-56 text-body-main place-content-center text-n-slate-10"
        >
          {{ t('CARTERA.RESUMEN.POR_VENCER_EMPTY') }}
        </p>

        <TableCard v-if="hasPorVencerData" class="mt-4">
          <ClickableTable
            :table="porVencerTable"
            @row-click="onPorVencerRowClick"
          />
        </TableCard>
      </Panel>

      <Panel :title="t('CARTERA.RESUMEN.PRESCRIPCION_TITLE')">
        <TableCard v-if="hasPrescripcionData">
          <ClickableTable :table="prescripcionTable" :clickable="false" />
        </TableCard>
        <p v-else class="text-sm text-n-slate-11">
          {{ t('CARTERA.RESUMEN.PRESCRIPCION_EMPTY') }}
        </p>
        <p class="mt-3 text-xs text-n-slate-10">
          {{ t('CARTERA.RESUMEN.PRESCRIPCION_AVISO') }}
        </p>
      </Panel>
    </template>
  </div>
</template>

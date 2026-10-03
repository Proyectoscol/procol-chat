<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { BarChart, LineChart } from '@chatwoot/viz';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import dashboardAPI from 'dashboard/api/cartera/dashboard';
import syncAPI from 'dashboard/api/cartera/syncs';
import MetricCard from '../cartera-shared/MetricCard.vue';
import Panel from '../cartera-shared/Panel.vue';
import { formatearCop } from '../cartera-shared/format';

const { t } = useI18n();
const { isAdmin } = useAdmin();

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

watch(sucursalSeleccionada, fetchResumen);
onMounted(fetchResumen);
</script>

<template>
  <div class="flex flex-col flex-1 h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex items-center justify-between gap-3 px-6 py-3 border-b border-n-weak flex-shrink-0"
    >
      <div class="flex items-center gap-3">
        <span class="i-lucide-layout-dashboard size-5 text-n-slate-11" />
        <h1 class="text-base font-semibold text-n-slate-12">
          {{ t('CARTERA.RESUMEN.TITLE') }}
        </h1>
      </div>
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
    </header>

    <div class="flex-1 overflow-y-auto p-6">
      <span
        v-if="isFetching && !resumen"
        class="flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{ t('CARTERA.RESUMEN.LOADING') }}
      </span>

      <template v-else-if="resumen">
        <div class="grid grid-cols-2 gap-4 mb-4 lg:grid-cols-4">
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
            <div v-if="hasAgingData" class="h-56">
              <BarChart
                :data="agingChartData"
                :format-value="formatearCop"
                :height="224"
                :show-values="false"
                :aria-label="t('CARTERA.RESUMEN.AGING_TITLE')"
              />
            </div>
            <div
              v-else
              class="grid h-56 text-body-main place-content-center text-n-slate-10"
            >
              {{ t('CARTERA.RESUMEN.AGING_EMPTY', { value: formatearCop(0) }) }}
            </div>

            <BaseTable
              v-if="hasAgingData"
              class="mt-4"
              :headers="[
                t('CARTERA.RESUMEN.TABLE_TRAMO'),
                t('CARTERA.RESUMEN.TABLE_FACTURAS'),
                t('CARTERA.RESUMEN.TABLE_VALOR'),
              ]"
              :items="resumen.tramos"
            >
              <template #row="{ items: rows }">
                <BaseTableRow v-for="row in rows" :key="row.tramo" :item="row">
                  <template #default>
                    <BaseTableCell>
                      <span class="text-body-main text-n-slate-12">
                        {{ tramoLabel(row.tramo) }}
                      </span>
                    </BaseTableCell>
                    <BaseTableCell align="end">
                      <span class="text-body-main text-n-slate-11">
                        {{ row.cantidad_facturas }}
                      </span>
                    </BaseTableCell>
                    <BaseTableCell align="end">
                      <span class="text-body-main text-n-slate-12 tabular-nums">
                        {{ formatearCop(row.valor_total) }}
                      </span>
                    </BaseTableCell>
                  </template>
                </BaseTableRow>
              </template>
            </BaseTable>
          </Panel>

          <Panel :title="t('CARTERA.RESUMEN.TENDENCIA_TITLE')">
            <div v-if="hasTendenciaData" class="h-56">
              <LineChart
                :data="tendenciaChartData"
                :format-value="formatearCop"
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

            <div v-if="hasTendenciaData" class="mt-4 max-h-56 overflow-y-auto">
              <BaseTable
                :headers="[
                  t('CARTERA.RESUMEN.TABLE_MES'),
                  t('CARTERA.RESUMEN.TABLE_VIGENTE'),
                  t('CARTERA.RESUMEN.TABLE_VENCIDO'),
                ]"
                :items="tendencia.puntos"
              >
                <template #row="{ items: rows }">
                  <BaseTableRow v-for="row in rows" :key="row.mes" :item="row">
                    <template #default>
                      <BaseTableCell>
                        <span class="text-body-main text-n-slate-12">
                          {{ row.mes }}
                        </span>
                      </BaseTableCell>
                      <BaseTableCell align="end">
                        <span
                          class="text-body-main text-n-teal-11 tabular-nums"
                        >
                          {{ formatearCop(row.valor_vigente) }}
                        </span>
                      </BaseTableCell>
                      <BaseTableCell align="end">
                        <span
                          class="text-body-main text-n-ruby-11 tabular-nums"
                        >
                          {{ formatearCop(row.valor_vencido) }}
                        </span>
                      </BaseTableCell>
                    </template>
                  </BaseTableRow>
                </template>
              </BaseTable>
            </div>
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
          <div v-if="hasPorVencerData" class="h-56">
            <BarChart
              :data="porVencerChartData"
              :format-value="formatearCop"
              :height="224"
              :show-values="false"
              :aria-label="t('CARTERA.RESUMEN.POR_VENCER_TITLE')"
            />
          </div>
          <p
            v-else
            class="grid h-56 text-body-main place-content-center text-n-slate-10"
          >
            {{ t('CARTERA.RESUMEN.POR_VENCER_EMPTY') }}
          </p>

          <BaseTable
            v-if="hasPorVencerData"
            class="mt-4"
            :headers="[
              t('CARTERA.RESUMEN.TABLE_TRAMO'),
              t('CARTERA.RESUMEN.TABLE_FACTURAS'),
              t('CARTERA.RESUMEN.TABLE_VALOR'),
            ]"
            :items="resumen.por_vencer"
          >
            <template #row="{ items: rows }">
              <BaseTableRow v-for="row in rows" :key="row.tramo" :item="row">
                <template #default>
                  <BaseTableCell>
                    <span class="text-body-main text-n-slate-12">
                      {{ tramoPorVencerLabel(row.tramo) }}
                    </span>
                  </BaseTableCell>
                  <BaseTableCell align="end">
                    <span class="text-body-main text-n-slate-11">
                      {{ row.cantidad_facturas }}
                    </span>
                  </BaseTableCell>
                  <BaseTableCell align="end">
                    <span class="text-body-main text-n-slate-12 tabular-nums">
                      {{ formatearCop(row.valor_total) }}
                    </span>
                  </BaseTableCell>
                </template>
              </BaseTableRow>
            </template>
          </BaseTable>
        </Panel>

        <Panel :title="t('CARTERA.RESUMEN.PRESCRIPCION_TITLE')">
          <BaseTable
            v-if="hasPrescripcionData"
            :headers="[
              t('CARTERA.RESUMEN.PRESCRIPCION_TABLE_VENTANA'),
              t('CARTERA.RESUMEN.TABLE_FACTURAS'),
              t('CARTERA.RESUMEN.TABLE_VALOR'),
            ]"
            :items="prescripcion.tramos.filter(tr => tr.cantidad_facturas > 0)"
          >
            <template #row="{ items: rows }">
              <BaseTableRow v-for="row in rows" :key="row.tramo" :item="row">
                <template #default>
                  <BaseTableCell>
                    <span class="text-body-main text-n-ruby-11">
                      {{
                        t(
                          `CARTERA.RESUMEN.PRESCRIPCION_VENTANAS.${row.tramo.toUpperCase()}`
                        )
                      }}
                    </span>
                  </BaseTableCell>
                  <BaseTableCell align="end">
                    <span class="text-body-main text-n-slate-11">
                      {{ row.cantidad_facturas }}
                    </span>
                  </BaseTableCell>
                  <BaseTableCell align="end">
                    <span class="text-body-main text-n-slate-12 tabular-nums">
                      {{ formatearCop(row.valor_en_riesgo) }}
                    </span>
                  </BaseTableCell>
                </template>
              </BaseTableRow>
            </template>
          </BaseTable>
          <p v-else class="text-sm text-n-slate-11">
            {{ t('CARTERA.RESUMEN.PRESCRIPCION_EMPTY') }}
          </p>
          <p class="mt-3 text-xs text-n-slate-10">
            {{ t('CARTERA.RESUMEN.PRESCRIPCION_AVISO') }}
          </p>
        </Panel>
      </template>
    </div>
  </div>
</template>

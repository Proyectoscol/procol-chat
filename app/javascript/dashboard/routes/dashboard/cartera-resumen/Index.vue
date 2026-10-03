<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { BarChart, LineChart } from '@chatwoot/viz';
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
const hasTendenciaData = computed(
  () => (tendencia.value?.puntos || []).length > 0
);

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
          />
          <MetricCard
            :label="t('CARTERA.RESUMEN.VALOR_VENCIDO')"
            :value="formatearCop(resumen.valor_vencido)"
          />
          <MetricCard
            :label="t('CARTERA.RESUMEN.CUPO_DISPONIBLE')"
            :value="formatearCop(resumen.cupo_disponible)"
          />
          <MetricCard
            :label="t('CARTERA.RESUMEN.FACTURAS_CALIDAD_DATOS')"
            :value="resumen.facturas_con_calidad_de_datos"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 mb-4 lg:grid-cols-2">
          <Panel :title="t('CARTERA.RESUMEN.AGING_TITLE')">
            <div v-if="hasAgingData" class="h-56">
              <BarChart
                :data="agingChartData"
                :format-value="formatearCop"
                :height="224"
                :aria-label="t('CARTERA.RESUMEN.AGING_TITLE')"
              />
            </div>
            <div
              v-else
              class="grid h-56 text-body-main place-content-center text-n-slate-10"
            >
              {{ t('CARTERA.RESUMEN.VALOR_TOTAL') }}: {{ formatearCop(0) }}
            </div>
          </Panel>

          <Panel :title="t('CARTERA.RESUMEN.TENDENCIA_TITLE')">
            <div v-if="hasTendenciaData" class="h-56">
              <LineChart
                :data="tendenciaChartData"
                :format-value="formatearCop"
                :height="224"
                :point-radius="2"
                :aria-label="t('CARTERA.RESUMEN.TENDENCIA_TITLE')"
              />
            </div>
            <div
              v-else
              class="grid h-56 text-body-main place-content-center text-n-slate-10"
            >
              {{ t('CARTERA.RESUMEN.PRESCRIPCION_EMPTY') }}
            </div>
          </Panel>
        </div>

        <Panel :title="t('CARTERA.RESUMEN.PRESCRIPCION_TITLE')">
          <div
            v-if="prescripcion?.tramos?.some(t2 => t2.cantidad_facturas > 0)"
            class="flex flex-wrap gap-3"
          >
            <div
              v-for="item in prescripcion.tramos.filter(
                t3 => t3.cantidad_facturas > 0
              )"
              :key="item.tramo"
              class="flex flex-col gap-1 px-4 py-3 rounded-lg border border-n-ruby-6 bg-n-ruby-3"
            >
              <span class="text-xs text-n-ruby-11">{{ item.tramo }}</span>
              <span class="text-sm font-medium text-n-slate-12">
                {{ item.cantidad_facturas }} ·
                {{ formatearCop(item.valor_en_riesgo) }}
              </span>
            </div>
          </div>
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

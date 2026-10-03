<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';
import facturaAPI from 'dashboard/api/cartera/facturas';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';
import ClickableTable from '../cartera-shared/ClickableTable.vue';
import MetricCard from '../cartera-shared/MetricCard.vue';
import Panel from '../cartera-shared/Panel.vue';
import { formatearCop, formatearFecha } from '../cartera-shared/format';

const DIAN_CUFE_URL = 'https://catalogo-vpfe.dian.gov.co/';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const isFetching = ref(false);
const factura = ref(null);

const sinDato = t('CARTERA.CLIENTES.SIN_DATO');

const colorTramo = tramo => {
  if (!tramo || tramo === 'vigente') return 'text-n-teal-11';
  if (['d1_30', 'd31_60'].includes(tramo)) return 'text-n-amber-11';
  return 'text-n-ruby-11';
};

const diasVencidosValor = computed(() => {
  if (!factura.value) return sinDato;
  if (!factura.value.pagada) {
    return factura.value.dias_vencidos > 0
      ? factura.value.dias_vencidos
      : t('CARTERA.FACTURA_FICHA.ESTADO_VIGENTE');
  }
  if (
    factura.value.dias_mora_pago === null ||
    factura.value.dias_mora_pago <= 0
  ) {
    return t('CARTERA.FACTURA_FICHA.PAGADA_A_TIEMPO');
  }
  return t('CARTERA.FACTURA_FICHA.PAGADA_CON_MORA', {
    dias: factura.value.dias_mora_pago,
  });
});

const estadoRadianColor = estado => {
  if (estado === 'ejecutable')
    return 'border-n-teal-6 bg-n-teal-3 text-n-teal-11';
  if (estado === 'en_reclamo')
    return 'border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11';
  if (estado === 'incompleta')
    return 'border-n-amber-6 bg-n-amber-3 text-n-amber-11';
  return 'border-n-slate-6 bg-n-slate-3 text-n-slate-11';
};

const fetchFactura = async () => {
  isFetching.value = true;
  try {
    const { data } = await facturaAPI.show(route.params.facturaId);
    factura.value = data;
  } finally {
    isFetching.value = false;
  }
};

const copiarCufe = async () => {
  try {
    await copyTextToClipboard(factura.value.cufe);
    useAlert(t('CARTERA.FACTURA_FICHA.CUFE_COPIADO'));
  } catch {
    useAlert(t('CARTERA.FACTURA_FICHA.CUFE_COPIAR_ERROR'));
  }
};

const irACliente = () => {
  router.push({
    name: 'cartera_clientes_ficha_view',
    params: { clienteId: factura.value.cliente_id },
  });
};

const columnHelper = createColumnHelper();
const radianColumns = [
  columnHelper.accessor('tipo_evento', {
    header: t('CARTERA.FACTURA_FICHA.RADIAN_HEADERS.EVENTO'),
    size: 220,
    cell: cellProps =>
      t(
        `CARTERA.FACTURA_FICHA.RADIAN_EVENTOS.${cellProps.getValue().toUpperCase()}`
      ),
  }),
  columnHelper.accessor('fecha', {
    header: t('CARTERA.FACTURA_FICHA.RADIAN_HEADERS.FECHA'),
    size: 150,
    cell: cellProps => formatearFecha(cellProps.getValue()),
  }),
  columnHelper.accessor('fuente', {
    header: t('CARTERA.FACTURA_FICHA.RADIAN_HEADERS.FUENTE'),
    size: 120,
    cell: cellProps => cellProps.getValue(),
  }),
];

const radianTable = useVueTable({
  get data() {
    return factura.value?.eventos_radian || [];
  },
  columns: radianColumns,
  enableSorting: false,
  getCoreRowModel: getCoreRowModel(),
});

onMounted(fetchFactura);
</script>

<template>
  <div>
    <CarteraHeader
      :header-title="factura ? factura.numero : ''"
      has-back-button
      :back-url="{ name: 'cartera_facturas_view' }"
    />

    <div
      v-if="isFetching && !factura"
      class="flex items-center justify-center py-20"
    >
      <Spinner />
    </div>

    <div v-else-if="factura" class="space-y-4 pb-6">
      <Panel :title="t('CARTERA.FACTURA_FICHA.DETALLE_TITLE')">
        <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <button type="button" class="text-left" @click="irACliente">
            <MetricCard
              :label="t('CARTERA.FACTURA_FICHA.DEUDOR')"
              :value="factura.nombre_cliente"
              value-class="text-n-blue-11 hover:underline"
            />
          </button>
          <MetricCard
            :label="t('CARTERA.FACTURA_FICHA.NIT')"
            :value="factura.identificacion_cliente"
          />
          <MetricCard
            :label="t('CARTERA.FACTURA_FICHA.FECHA_EMISION')"
            :value="formatearFecha(factura.fecha_emision)"
          />
          <MetricCard
            :label="t('CARTERA.FACTURA_FICHA.FECHA_VENCIMIENTO')"
            :value="formatearFecha(factura.fecha_vencimiento)"
          />
          <MetricCard
            :label="t('CARTERA.FACTURA_FICHA.VALOR_TOTAL')"
            :value="formatearCop(factura.valor_total)"
          />
          <MetricCard
            :label="t('CARTERA.FACTURA_FICHA.SALDO_PENDIENTE')"
            :value="formatearCop(factura.saldo_pendiente)"
          />
          <MetricCard
            :label="t('CARTERA.FACTURA_FICHA.DIAS_VENCIDOS')"
            :value="diasVencidosValor"
            :value-class="
              factura.pagada ? 'text-n-teal-11' : colorTramo(factura.tramo)
            "
          />
          <MetricCard
            v-if="factura.pagada"
            :label="t('CARTERA.FICHA.PAGOS_TITLE')"
            :value="
              factura.fecha_pago
                ? t('CARTERA.FACTURA_FICHA.PAGADA_EL', {
                    fecha: formatearFecha(factura.fecha_pago),
                  })
                : sinDato
            "
          />
        </div>
      </Panel>

      <Panel :title="t('CARTERA.FACTURA_FICHA.CUFE_TITLE')">
        <div v-if="factura.cufe" class="flex flex-wrap items-center gap-3">
          <code
            class="px-3 py-2 rounded-lg bg-n-slate-2 text-xs text-n-slate-12 break-all"
          >
            {{ factura.cufe }}
          </code>
          <Button
            icon="i-lucide-copy"
            slate
            faded
            size="sm"
            :label="t('CARTERA.FACTURA_FICHA.CUFE_COPIAR')"
            @click="copiarCufe"
          />
          <a :href="DIAN_CUFE_URL" target="_blank" rel="noopener noreferrer">
            <Button
              icon="i-lucide-external-link"
              slate
              faded
              size="sm"
              :label="t('CARTERA.FACTURA_FICHA.CONSULTAR_DIAN')"
            />
          </a>
        </div>
        <p v-else class="text-sm text-n-slate-11">
          {{ t('CARTERA.FACTURA_FICHA.CUFE_SIN_DATO') }}
        </p>
      </Panel>

      <Panel :title="t('CARTERA.FACTURA_FICHA.RADIAN_TITLE')">
        <template v-if="factura.radian" #actions>
          <span
            class="rounded-full border px-2 py-0.5 text-[10px] whitespace-nowrap"
            :class="estadoRadianColor(factura.radian.estado)"
          >
            {{
              t(
                `CARTERA.FACTURA_FICHA.RADIAN_ESTADOS.${factura.radian.estado.toUpperCase()}`
              )
            }}
          </span>
        </template>

        <TableCard v-if="factura.eventos_radian.length" class="mb-3">
          <ClickableTable :table="radianTable" :clickable="false" />
        </TableCard>
        <p v-else class="text-sm text-n-slate-11">
          {{ t('CARTERA.FACTURA_FICHA.RADIAN_EMPTY') }}
        </p>

        <ul
          v-if="
            factura.eventos_radian.length && factura.radian?.supuestos?.length
          "
          class="mt-3 list-disc pl-5 text-xs text-n-slate-10 space-y-1"
        >
          <li v-for="(supuesto, idx) in factura.radian.supuestos" :key="idx">
            {{ supuesto }}
          </li>
        </ul>
        <p class="mt-3 text-xs text-n-slate-10">
          {{ t('CARTERA.FACTURA_FICHA.RADIAN_AVISO') }}
        </p>
      </Panel>
    </div>
  </div>
</template>

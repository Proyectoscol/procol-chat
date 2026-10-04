<!-- Vista rapida de las facturas detras de un tramo/tarjeta de Resumen, sin
salir de la pagina: un preview con scroll, acceso directo a cada factura, un
link a la lista completa con el mismo filtro ya aplicado, y la exportacion
CSV de exactamente lo que se esta viendo. -->
<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import facturaAPI from 'dashboard/api/cartera/facturas';
import FacturasTable from './FacturasTable.vue';
import { formatearCop } from './format';

const { t } = useI18n();
const router = useRouter();

const dialogRef = ref(null);
const isFetching = ref(false);
const items = ref([]);
const total = ref(0);
const titulo = ref('');
const filtro = ref({ tramo: '', estado: '' });

const totalMostrado = computed(() =>
  items.value.reduce((sum, f) => sum + f.saldo_pendiente, 0)
);

const fetchItems = async () => {
  isFetching.value = true;
  try {
    const { data } = await facturaAPI.get({ ...filtro.value, pageSize: 50 });
    items.value = data.items;
    total.value = data.total;
  } finally {
    isFetching.value = false;
  }
};

const abrir = async ({ tramo = '', estado = '', label }) => {
  filtro.value = { tramo, estado };
  titulo.value = label;
  dialogRef.value?.open();
  await fetchItems();
};

const verTodas = () => {
  dialogRef.value?.close();
  router.push({ name: 'cartera_facturas_view', query: filtro.value });
};

const exportUrl = computed(() => facturaAPI.exportUrl(filtro.value));

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="titulo"
    width="2xl"
    overflow-y-auto
    :show-cancel-button="false"
    :show-confirm-button="false"
  >
    <div
      v-if="isFetching && !items.length"
      class="flex items-center justify-center py-10"
    >
      <span class="i-lucide-loader-2 animate-spin size-5 text-n-slate-10" />
    </div>
    <template v-else>
      <p class="text-sm text-n-slate-11">
        {{
          t('CARTERA.RESUMEN.DETALLE_RESUMEN', {
            count: total,
            valor: formatearCop(totalMostrado),
          })
        }}
      </p>
      <div class="max-h-[22rem] overflow-y-auto">
        <FacturasTable
          :items="items"
          :empty-message="t('CARTERA.FACTURAS.EMPTY_STATE')"
        />
      </div>
      <div class="flex items-center justify-between gap-3 pt-2">
        <a :href="exportUrl">
          <Button
            icon="i-lucide-download"
            slate
            faded
            size="sm"
            :label="t('CARTERA.EXPORTAR_CSV')"
          />
        </a>
        <Button
          size="sm"
          :label="t('CARTERA.RESUMEN.VER_TODAS_FACTURAS')"
          @click="verTodas"
        />
      </div>
    </template>
  </Dialog>
</template>

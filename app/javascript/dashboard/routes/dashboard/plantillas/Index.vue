<script setup>
import { ref, reactive, computed, h, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useVueTable,
  createColumnHelper,
  getCoreRowModel,
} from '@tanstack/vue-table';
import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import plantillaAPI from 'dashboard/api/cartera/plantillasWhatsapp';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';
import ClickableTable from '../cartera-shared/ClickableTable.vue';

const { t } = useI18n();
const { isAdmin } = useAdmin();

const categoriaOptions = computed(() => [
  { value: 'utility', label: t('CARTERA.PLANTILLAS.CATEGORIAS.UTILITY') },
  { value: 'marketing', label: t('CARTERA.PLANTILLAS.CATEGORIAS.MARKETING') },
  {
    value: 'authentication',
    label: t('CARTERA.PLANTILLAS.CATEGORIAS.AUTHENTICATION'),
  },
]);

const estadoBadgeClass = plantilla => {
  const estado = plantilla.estado_twilio || plantilla.estado;
  if (estado === 'approved')
    return 'border-n-teal-6 bg-n-teal-3 text-n-teal-11';
  if (['rejected', 'failed'].includes(estado)) {
    return 'border-n-ruby-6 bg-n-ruby-3 text-n-ruby-11';
  }
  if (estado === 'enviada' || estado === 'pending') {
    return 'border-n-amber-6 bg-n-amber-3 text-n-amber-11';
  }
  return 'border-n-slate-6 bg-n-slate-3 text-n-slate-11';
};

const estadoLabel = plantilla => {
  const estado = plantilla.estado_twilio || plantilla.estado;
  return t(`CARTERA.PLANTILLAS.ESTADOS.${estado.toUpperCase()}`, estado);
};

const items = ref([]);
const isFetching = ref(false);

const fetchPlantillas = async () => {
  isFetching.value = true;
  try {
    const { data } = await plantillaAPI.get();
    items.value = data;
  } finally {
    isFetching.value = false;
  }
};

const spanCell = (value, className = 'text-body-main text-n-slate-12') =>
  h('span', { class: className }, value);

const solicitandoId = ref(null);

const solicitarAprobacion = async plantilla => {
  solicitandoId.value = plantilla.id;
  try {
    await plantillaAPI.solicitarAprobacion(plantilla.id);
    useAlert(t('CARTERA.PLANTILLAS.SOLICITUD_EXITOSA'));
    await fetchPlantillas();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CARTERA.PLANTILLAS.SOLICITUD_ERROR')
    );
  } finally {
    solicitandoId.value = null;
  }
};

const columnHelper = createColumnHelper();
const columns = [
  columnHelper.accessor('nombre', {
    header: t('CARTERA.PLANTILLAS.HEADERS.NOMBRE'),
    size: 200,
    cell: cellProps => spanCell(cellProps.getValue()),
  }),
  columnHelper.accessor('categoria', {
    header: t('CARTERA.PLANTILLAS.HEADERS.CATEGORIA'),
    size: 140,
    cell: cellProps =>
      spanCell(
        t(
          `CARTERA.PLANTILLAS.CATEGORIAS.${cellProps.getValue().toUpperCase()}`
        ),
        'text-body-main text-n-slate-11'
      ),
  }),
  columnHelper.accessor('cuerpo', {
    header: t('CARTERA.PLANTILLAS.HEADERS.CUERPO'),
    size: 320,
    cell: cellProps =>
      spanCell(
        cellProps.getValue(),
        'text-body-main text-n-slate-11 line-clamp-2'
      ),
  }),
  columnHelper.accessor('estado', {
    header: t('CARTERA.PLANTILLAS.HEADERS.ESTADO'),
    size: 130,
    cell: cellProps => {
      const plantilla = cellProps.row.original;
      return h(
        'span',
        {
          class: `inline-block rounded-full border px-2 py-0.5 text-xs whitespace-nowrap ${estadoBadgeClass(plantilla)}`,
        },
        estadoLabel(plantilla)
      );
    },
  }),
  columnHelper.display({
    id: 'acciones',
    header: t('CARTERA.PLANTILLAS.HEADERS.ACCIONES'),
    size: 160,
    cell: cellProps => {
      const plantilla = cellProps.row.original;
      if (plantilla.content_sid || !isAdmin.value) return null;
      return h(Button, {
        size: 'sm',
        slate: true,
        faded: true,
        label: t('CARTERA.PLANTILLAS.SOLICITAR_APROBACION'),
        isLoading: solicitandoId.value === plantilla.id,
        onClick: () => solicitarAprobacion(plantilla),
      });
    },
  }),
];

const table = useVueTable({
  get data() {
    return items.value;
  },
  columns,
  getCoreRowModel: getCoreRowModel(),
});

const dialogRef = ref(null);
const isSaving = ref(false);
const form = reactive({ nombre: '', categoria: 'utility', cuerpo: '' });

const abrirDialogo = () => {
  form.nombre = '';
  form.categoria = 'utility';
  form.cuerpo = '';
  dialogRef.value?.open();
};

const crearPlantilla = async () => {
  isSaving.value = true;
  try {
    await plantillaAPI.create({ ...form });
    useAlert(t('CARTERA.PLANTILLAS.CREADA_EXITOSA'));
    dialogRef.value?.close();
    await fetchPlantillas();
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CARTERA.PLANTILLAS.CREADA_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

onMounted(fetchPlantillas);
</script>

<template>
  <div>
    <CarteraHeader :header-title="t('CARTERA.PLANTILLAS.TITLE')">
      <Button
        v-if="isAdmin"
        icon="i-lucide-plus"
        size="sm"
        :label="t('CARTERA.PLANTILLAS.NUEVA')"
        @click="abrirDialogo"
      />
    </CarteraHeader>

    <TableCard>
      <ClickableTable :table="table" :clickable="false" />
    </TableCard>

    <div
      v-if="isFetching && !items.length"
      class="flex items-center justify-center py-16"
    >
      <Spinner />
    </div>
    <EmptyState
      v-else-if="!isFetching && !items.length"
      :title="t('CARTERA.PLANTILLAS.EMPTY_STATE')"
    />

    <Dialog
      ref="dialogRef"
      :title="t('CARTERA.PLANTILLAS.NUEVA')"
      :description="t('CARTERA.PLANTILLAS.NUEVA_DESCRIPCION')"
      :confirm-button-label="t('CARTERA.PLANTILLAS.GUARDAR')"
      :is-loading="isSaving"
      :disable-confirm-button="!form.nombre || !form.cuerpo"
      @confirm="crearPlantilla"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.nombre"
          :label="t('CARTERA.PLANTILLAS.FORM.NOMBRE')"
          :placeholder="t('CARTERA.PLANTILLAS.FORM.NOMBRE_PLACEHOLDER')"
        />
        <div class="flex flex-col gap-1">
          <label class="text-sm text-n-slate-12">
            {{ t('CARTERA.PLANTILLAS.FORM.CATEGORIA') }}
          </label>
          <Select v-model="form.categoria" :options="categoriaOptions" />
        </div>
        <TextArea
          v-model="form.cuerpo"
          :label="t('CARTERA.PLANTILLAS.FORM.CUERPO')"
          :placeholder="t('CARTERA.PLANTILLAS.FORM.CUERPO_PLACEHOLDER')"
          :max-length="1024"
          show-character-count
          auto-height
        />
        <p class="text-n-slate-11 text-sm mb-0">
          {{ t('CARTERA.PLANTILLAS.FORM.CUERPO_AYUDA') }}
        </p>
      </div>
    </Dialog>
  </div>
</template>
